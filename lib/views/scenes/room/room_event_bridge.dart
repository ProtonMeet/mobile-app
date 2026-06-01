import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/helper/logger.dart' as l;
// import 'package:meet/helper/participant_stat_logger.dart';
import 'package:meet/managers/channels/call_activity_channel.dart';

import 'room_event.dart';
import 'room_event_livekit.dart';
import 'room_state.dart';

mixin RoomEventsBinding on Bloc<RoomBlocEvent, RoomState> {
  @override
  Future<void> close() {
    _bound = false;
    _signalListener.cancelAll();
    _signalListener.dispose();
    // _participantStatLogger.dispose();
    return super.close();
  }

  bool _bound = false;
  late EventsListener<SignalEvent> _signalListener;
  final Set<String> _pendingSubscribeSids = <String>{};

  /// logger for participant stats
  // final _participantStatLogger = ParticipantStatLogger();

  // String exportAllStatsAsJson() {
  //   return _participantStatLogger.exportAllStatsAsJson();
  // }

  // void logSystemLogToStatLogger(int timestamp, String log) {
  //   _participantStatLogger.logSystemLog(timestamp, log);
  // }

  /// Handles unsubscribing video tracks by default if the feature is enabled.
  /// This is used when tracks are published or subscribed.
  void _handleUnsubscribeVideoByDefault(TrackPublication publication) {
    final unsubscribeVideoByDefault = state.unsubscribeVideoByDefault;
    if (unsubscribeVideoByDefault) {
      // check if the track is video and unsubscribe it (we will keep screen share tracks subscribed)
      if (publication.track is RemoteVideoTrack &&
          publication is RemoteTrackPublication &&
          !publication.isScreenShare) {
        publication.unsubscribe();
      }
    }
  }

  /// Handles muting audio tracks if speaker is muted.
  /// This is used when audio tracks are published or subscribed.
  Future<void> _handleMuteAudioTrackIfSpeakerMuted(
    Participant participant,
  ) async {
    final isSpeakerMuted = state.isSpeakerMuted ?? false;
    l.logger.d('[LiveKit] isSpeakerMuted: $isSpeakerMuted');
    if (!isSpeakerMuted || participant is! RemoteParticipant) {
      return;
    }

    final remoteParticipant = participant;
    for (final pub in remoteParticipant.audioTrackPublications) {
      // Only disable if the track is subscribed and available
      if (pub.subscribed) {
        final track = pub.track;
        if (track != null) {
          try {
            // Use microtask to ensure track is fully ready after unmute event
            // This allows the track to complete its internal state transitions
            await Future.microtask(() async {
              // Double-check track is still available and subscribed
              if (pub.subscribed && pub.track != null) {
                await track.disable();
                l.logger.d('[LiveKit] Muted audio track: ${track.sid}');
              }
            });
          } catch (e) {
            l.logger.e('[LiveKit] Error muting audio track: $e');
          }
        }
      }
    }
  }

  /// Subscribe a single publication if it is audio (mic / screen-share audio)
  /// or screen-share video. Camera video is intentionally left for the UI
  /// grid to subscribe on demand (see ResponsiveCameraLayout).
  ///
  /// Idempotent: bails when the publication is already subscribed.
  ///
  /// Companion to `autoSubscribe: false` in [RoomManager.connectRoom]. With
  /// auto-subscribe disabled the SFU only forwards tracks we explicitly
  /// subscribe to, so we must run this anywhere the room exposes a new (or
  /// re-published) track: initial roster walk, ParticipantConnected,
  /// TrackPublished, and as a defensive re-subscribe on TrackUnmuted.
  void _subscribeIfAudioOrScreenShare(RemoteTrackPublication pub) {
    if (pub.subscribed) return;
    final shouldSubscribe = pub.kind == TrackType.AUDIO || pub.isScreenShare;
    if (!shouldSubscribe) return;

    // Race-window dedup: Set.add returns false if the sid is already
    // pending, meaning a previous call has already sent UpdateSubscription
    // and we are still waiting for TrackSubscribedEvent. Bail to avoid a
    // duplicate RPC to the SFU.
    if (!_pendingSubscribeSids.add(pub.sid)) return;

    try {
      pub.subscribe();
      l.logger.d(
        '[LiveKit] subscribe sid=${pub.sid} kind=${pub.kind} '
        'source=${pub.source} (autoSubscribe=false policy)',
      );
    } catch (e) {
      // Allow a future retry: the in-flight request never made it out.
      _pendingSubscribeSids.remove(pub.sid);
      l.logger.e('[LiveKit] subscribe failed sid=${pub.sid}: $e');
    }
  }

  /// Walk one remote participant's publications and apply the audio +
  /// screen-share subscribe policy.
  void _subscribeAudioAndScreenShareForParticipant(
    RemoteParticipant participant,
  ) {
    for (final pub in participant.trackPublications.values) {
      _subscribeIfAudioOrScreenShare(pub);
    }
  }

  /// Walk the room's current remote roster once and apply the audio +
  /// screen-share subscribe policy. Called right after listeners are wired
  /// so participants/tracks that already existed at connect time are not
  /// missed (TrackPublishedEvent only covers tracks published after we
  /// start listening).
  void _subscribeExistingAudioAndScreenShare() {
    for (final participant in state.room.remoteParticipants.values) {
      _subscribeAudioAndScreenShareForParticipant(participant);
    }
  }

  void setUpListeners() {
    if (_bound) return;
    _bound = true;

    /// for more information, see [event types](https://docs.livekit.io/client/events/#events)
    state.listener
      ..on<RoomDisconnectedEvent>((event) async {
        // Drop the in-flight guard; pubs from this connection are stale.
        _pendingSubscribeSids.clear();

        /// End call activity when room disconnects
        await CallActivityChannel.end(immediately: true);
      })
      ..on<RoomAttemptReconnectEvent>((event) {
        add(const SetLiveKitReconnecting(isLiveKitReconnecting: true));
      })
      ..on<RoomReconnectingEvent>((event) {
        add(const SetLiveKitReconnecting(isLiveKitReconnecting: true));
      })
      ..on<RoomReconnectedEvent>((event) {
        add(const SetLiveKitReconnecting(isLiveKitReconnecting: false));
      })
      ..on<ParticipantEvent>((event) {
        // Use debounced sort for high-frequency participant events to reduce CPU load
        // with large participant counts
        add(DebouncedSortParticipants());
        // _updateParticipantLogger();
      })
      ..on<RoomRecordingStatusChanged>((event) {
        /// widget will handle it
      })
      ..on<LocalTrackPublishedEvent>((_) {
        add(
          DebouncedSortParticipants(),
        ); // Schedule logger update on next microtask to avoid blocking event loop
        // Future.microtask(_updateParticipantLogger);
        // Centralized E2EE key refresh: LiveKit builds a fresh frame
        // cryptor per published track. If a key rotation was mid-flight
        // at publish time the cryptor can pin to a stale keyIndex,
        // breaking decryption on remote (web) peers until the next epoch
        // change. Re-arm the key here so it covers every local publish
        // path (mic / camera / screen-share / fastConnect / rejoin)
        // without each call site having to remember.
        add(const BridgeLocalTrackPublished());
      })
      ..on<LocalTrackUnpublishedEvent>((event) {
        add(DebouncedSortParticipants());
      })
      ..on<ParticipantConnectedEvent>((event) async {
        add(BridgeParticipantConnected(event));
        // Cover the gap between ParticipantConnectedEvent and the per-track
        // TrackPublishedEvent: if the joiner already had publications at
        // connect time, subscribe to their audio + screen-share immediately.
        // Idempotent with the TrackPublishedEvent handler below.
        _subscribeAudioAndScreenShareForParticipant(event.participant);
      })
      ..on<ParticipantDisconnectedEvent>((event) {
        // Defensive: drop all pending sids belonging to this participant
        // in case TrackUnsubscribedEvent does not fire on disconnect
        // (e.g. abrupt network drop). Cheap O(K) scan where K is the
        // small set of in-flight subscribes. Done before the rejoin
        // short-circuit so the guard is freed even on stale events.
        for (final pub in event.participant.trackPublications.values) {
          _pendingSubscribeSids.remove(pub.sid);
        }

        // During rejoin, the old room is torn down and may emit stale ParticipantDisconnectedEvent.
        // Ignore these to avoid surfacing false leave/chat events.
        if (state.isRejoining || state.isLiveKitReconnecting) {
          l.logger.w(
            '[LiveKit] Skip disconnect side effects during rejoin for '
            '${event.participant.identity}',
          );
          return;
        }
        add(BridgeParticipantDisconnected(event));
        add(
          AddSystemMessage(
            'Participant disconnected: ${event.participant.identity}',
            event.participant.identity,
            event.participant.name,
          ),
        );
      })
      ..on<TrackSubscribedEvent>((event) async {
        // Race resolved: SDK now owns `pub.subscribed == true` for this
        // sid. Free the in-flight slot so any future re-subscribe (after
        // an explicit unsubscribe) is allowed through.
        _pendingSubscribeSids.remove(event.publication.sid);

        _handleUnsubscribeVideoByDefault(event.publication);
        await _handleMuteAudioTrackIfSpeakerMuted(event.participant);
        // Schedule codec logging asynchronously to avoid blocking event loop
        if (kDebugMode) {
          Future.microtask(() => _logParticipantCodecs(event.participant));
        }
        add(DebouncedSortParticipants());
      })
      ..on<TrackPublishedEvent>((event) async {
        // Apply the audio + screen-share subscribe policy on every newly
        // published track (autoSubscribe: false means nothing flows
        // otherwise). Camera video is intentionally skipped here.
        _subscribeIfAudioOrScreenShare(event.publication);
        await _handleMuteAudioTrackIfSpeakerMuted(event.participant);
        _handleUnsubscribeVideoByDefault(event.publication);
      })
      ..on<TrackUnmutedEvent>((event) async {
        // Defensive re-subscribe: if the audio publication had been
        // unsubscribed (e.g. because the participant joined muted and no
        // initial subscribe happened, or a future bandwidth optimization
        // dropped idle mics), pull it back here so the unmute is audible.
        // No-op when already subscribed.
        final pub = event.publication;
        if (pub is RemoteTrackPublication) {
          _subscribeIfAudioOrScreenShare(pub);
        }
        await _handleMuteAudioTrackIfSpeakerMuted(event.participant);
        _handleUnsubscribeVideoByDefault(event.publication);
      })
      ..on<TrackStreamStateUpdatedEvent>((event) async {
        await _handleMuteAudioTrackIfSpeakerMuted(event.participant);
        _handleUnsubscribeVideoByDefault(event.publication);
      })
      ..on<TrackUnsubscribedEvent>((event) {
        // Allow a future re-subscribe for this sid (e.g. user switches
        // back to screen-share view, or layout brings a tile into view).
        _pendingSubscribeSids.remove(event.publication.sid);

        add(DebouncedSortParticipants());
      })
      ..on<ParticipantNameUpdatedEvent>((event) {
        add(DebouncedSortParticipants());
      })
      ..on<DataReceivedEvent>((event) async {
        add(BridgeDataReceived(event));
      });

    // ignore: invalid_use_of_internal_member
    _signalListener = state.room.engine.signalClient.createListener();
    _signalListener.on<SignalEvent>((event) {
      // l.logger.d('engine signal event: $event');
      final typeName = event.runtimeType.toString();
      if (typeName.contains('Token') || typeName == 'SignalTokenUpdatedEvent') {
        // ignore: invalid_use_of_internal_member
        final newToken = state.room.engine.token;
        l.logger.d("[LiveKit] Detected token refresh: $newToken");
        if (newToken != null) {
          add(BridgeTokenUpdated(newToken));
        }
      }
    });

    // Initial roster walk: with autoSubscribe: false, the room is connected
    // but no media is flowing. Pull all existing audio and screen-share
    // tracks now; camera video is left for the UI grid to subscribe on
    // demand (ResponsiveCameraLayout._updateVideoSubscriptions).
    _subscribeExistingAudioAndScreenShare();
    // add more mappings as needed...
  }

  // Add this function to debug WebRTC codec negotiation
  void _logParticipantCodecs(Participant participant) {
    try {
      // Use a StringBuilder pattern for efficient logging
      final StringBuffer logMsg = StringBuffer(
        '=== WebRTC Codec Info for ${participant.identity} ===\n',
      );

      // Also add a debug listener for each track publication
      if (participant is LocalParticipant) {
        if (participant.videoTrackPublications.isNotEmpty) {
          logMsg.writeln('Local video tracks:');
          for (var pub in participant.videoTrackPublications) {
            // Debug sender tracks
            logMsg.writeln('  - Local video track: ${pub.sid}');
            if (pub.track != null) {
              logMsg.writeln('    - mimeType: ${pub.mimeType}');
            }
          }
        }

        if (participant.audioTrackPublications.isNotEmpty) {
          logMsg.writeln('\nLocal audio tracks:');
          for (var pub in participant.audioTrackPublications) {
            logMsg.writeln('  - Local audio track: ${pub.sid}');
            if (pub.track != null) {
              logMsg.writeln('    - mimeType: ${pub.mimeType}');
            }
          }
        }
      } else if (participant is RemoteParticipant) {
        if (participant.videoTrackPublications.isNotEmpty) {
          logMsg.writeln('Remote video tracks:');
          for (var pub in participant.videoTrackPublications) {
            logMsg.writeln('  - Remote video track: ${pub.sid}');
            logMsg.writeln('    - mimeType: ${pub.mimeType}');
          }
        }

        if (participant.audioTrackPublications.isNotEmpty) {
          logMsg.writeln('\nRemote audio tracks:');
          for (var pub in participant.audioTrackPublications) {
            logMsg.writeln('  - Remote audio track: ${pub.sid}');
            logMsg.writeln('    - mimeType: ${pub.mimeType}');
          }
        }
      }

      // Log all info in a single call
      l.logger.d(logMsg.toString());
    } catch (e) {
      l.logger.e('Error logging codec info: $e');
    }
  }

  // void _updateParticipantLogger() {
  //   if (state.room.localParticipant != null) {
  //     _participantStatLogger.addParticipant(state.room.localParticipant!);
  //   }
  //   for (var participant in state.room.remoteParticipants.values) {
  //     _participantStatLogger.addParticipant(participant);
  //   }
  // }
}
