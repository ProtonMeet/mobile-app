import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/helper/extension/remote_track_publication_extension.dart';
import 'package:meet/helper/subscribe_retry_backoff.dart';
import 'package:meet/helper/logger.dart' as l;
// import 'package:meet/helper/participant_stat_logger.dart';
import 'package:meet/managers/channels/call_activity_channel.dart';
import 'package:meet/managers/room.manager.dart' show RoomManager;

import 'room_bloc_pip.dart';
import 'room_event.dart';
import 'room_event_livekit.dart';
import 'room_state.dart';

mixin RoomEventsBinding on Bloc<RoomBlocEvent, RoomState>, RoomPipHandlers {
  @override
  Future<void> close() {
    _bound = false;
    _clearAllPendingSubscribes(clearRetryCounts: true);
    _signalListener.cancelAll();
    _signalListener.dispose();
    // _participantStatLogger.dispose();
    return super.close();
  }

  bool _bound = false;
  bool _reconcilingInFlightAudioSubscribes = false;
  DateTime? _lastAudioReconcileAt;
  late EventsListener<SignalEvent> _signalListener;
  final Set<String> _pendingSubscribeSids = <String>{};
  final Map<String, Timer> _pendingSubscribeTimeouts = <String, Timer>{};
  final Map<String, int> _subscribeRetryCounts = <String, int>{};
  final Set<String> _bindingWaitSids = <String>{};

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

  void _clearPendingSubscribe(String sid) {
    _pendingSubscribeSids.remove(sid);
    _pendingSubscribeTimeouts.remove(sid)?.cancel();
  }

  void _clearAllPendingSubscribes({bool clearRetryCounts = false}) {
    _pendingSubscribeSids.clear();
    for (final timer in _pendingSubscribeTimeouts.values) {
      timer.cancel();
    }
    _pendingSubscribeTimeouts.clear();
    _bindingWaitSids.clear();
    _lastAudioReconcileAt = null;
    if (clearRetryCounts) {
      _subscribeRetryCounts.clear();
    }
  }

  void _armSubscribeTimeout(RemoteTrackPublication pub) {
    final sid = pub.sid;
    _pendingSubscribeTimeouts[sid]?.cancel();
    _pendingSubscribeTimeouts[sid] = Timer(audioSubscribeTimeout, () {
      _pendingSubscribeTimeouts.remove(sid);
      if (!_pendingSubscribeSids.contains(sid)) {
        return;
      }
      _pendingSubscribeSids.remove(sid);
      l.logger.w(
        '[LiveKit] subscribe timeout sid=$sid kind=${pub.kind} '
        'source=${pub.source} after ${audioSubscribeTimeout.inSeconds}s',
      );
      _scheduleSubscribeRetry(pub);
    });
  }

  Duration _subscribeRetryBackoff(int retryIndex) {
    return subscribeRetryBackoffWithJitter(
      baseDelay: audioSubscribeRetryBaseDelay,
      retryIndex: retryIndex,
      maxDelay: audioSubscribeRetryMaxDelay,
    );
  }

  bool get _hasInFlightSubscribeWork =>
      _pendingSubscribeSids.isNotEmpty ||
      _bindingWaitSids.isNotEmpty ||
      _pendingSubscribeTimeouts.isNotEmpty;

  bool _isPendingAudioSid(String sid) {
    for (final participant in state.room.remoteParticipants.values) {
      for (final pub in participant.audioTrackPublications) {
        if (pub.sid == sid) {
          return true;
        }
      }
    }
    return false;
  }

  bool get _hasInFlightAudioSubscribeWork {
    if (!_hasInFlightSubscribeWork) {
      return false;
    }
    for (final sid in _pendingSubscribeSids) {
      if (_isPendingAudioSid(sid)) {
        return true;
      }
    }
    for (final sid in _bindingWaitSids) {
      if (_isPendingAudioSid(sid)) {
        return true;
      }
    }
    for (final sid in _pendingSubscribeTimeouts.keys) {
      if (_isPendingAudioSid(sid)) {
        return true;
      }
    }
    return false;
  }

  void _scheduleSubscribeRetry(RemoteTrackPublication pub) {
    final sid = pub.sid;
    final retries = _subscribeRetryCounts[sid] ?? 0;
    if (retries >= maxAudioSubscribeRetries) {
      l.logger.w('[LiveKit] subscribe retry exhausted sid=$sid');
      _subscribeRetryCounts.remove(sid);
      return;
    }

    _subscribeRetryCounts[sid] = retries + 1;
    final backoff = _subscribeRetryBackoff(retries);
    l.logger.d(
      '[LiveKit] scheduling subscribe retry ${retries + 1}/'
      '$maxAudioSubscribeRetries sid=$sid in ${backoff.inMilliseconds}ms',
    );
    Timer(backoff, () {
      if (isClosed) {
        return;
      }
      unawaited(_retrySubscribe(pub));
    });
  }

  Future<void> _retrySubscribe(RemoteTrackPublication pub) async {
    if (!_shouldAutoSubscribe(pub)) {
      return;
    }

    if (pub.subscribed && pub.track != null) {
      _clearPendingSubscribe(pub.sid);
      _subscribeRetryCounts.remove(pub.sid);
      return;
    }

    _clearPendingSubscribe(pub.sid);

    if (pub.subscribed && pub.track == null) {
      try {
        await pub.unsubscribe();
        l.logger.d(
          '[LiveKit] unsubscribed stuck publication sid=${pub.sid} before retry',
        );
      } catch (e) {
        l.logger.e(
          '[LiveKit] unsubscribe before subscribe retry failed '
          'sid=${pub.sid}: $e',
        );
      }
    }

    _subscribeIfAudioOrScreenShare(pub);
  }

  void _scheduleSubscribedTrackBindWait(RemoteTrackPublication pub) {
    if (!_shouldAutoSubscribe(pub) || !pub.subscribed || pub.track != null) {
      return;
    }
    if (!_bindingWaitSids.add(pub.sid)) {
      return;
    }

    unawaited(() async {
      try {
        final bound = await pub.waitForTrackBound();
        if (bound) {
          _clearPendingSubscribe(pub.sid);
          _subscribeRetryCounts.remove(pub.sid);
          return;
        }

        l.logger.w(
          '[LiveKit] subscribed-but-unbound timeout sid=${pub.sid} '
          'kind=${pub.kind} source=${pub.source}',
        );
        _scheduleSubscribeRetry(pub);
      } finally {
        _bindingWaitSids.remove(pub.sid);
      }
    }());
  }

  bool _shouldAutoSubscribe(RemoteTrackPublication pub) {
    return pub.kind == TrackType.AUDIO || pub.isScreenShare;
  }

  void _subscribeIfAudio(RemoteTrackPublication pub) {
    if (pub.kind != TrackType.AUDIO) {
      return;
    }
    _subscribePublication(pub);
  }

  void _subscribeIfScreenShare(RemoteTrackPublication pub) {
    if (!pub.isScreenShare) {
      return;
    }
    _subscribePublication(pub);
  }

  /// Subscribe a single publication if it is audio (mic / screen-share audio)
  /// or screen-share video. Camera video is intentionally left for the UI
  /// grid to subscribe on demand (see ResponsiveCameraLayout).
  ///
  /// Idempotent: bails when the publication is already subscribed and bound.
  ///
  /// Companion to `autoSubscribe: false` in [RoomManager.connectRoom]. With
  /// auto-subscribe disabled the SFU only forwards tracks we explicitly
  /// subscribe to, so we must run this anywhere the room exposes a new (or
  /// re-published) track: initial roster walk, ParticipantConnected,
  /// TrackPublished, and as a defensive re-subscribe on TrackUnmuted.
  void _subscribeIfAudioOrScreenShare(RemoteTrackPublication pub) {
    if (!_shouldAutoSubscribe(pub)) {
      return;
    }
    _subscribePublication(pub);
  }

  void _subscribePublication(RemoteTrackPublication pub) {
    if (pub.subscribed) {
      if (pub.track != null) {
        _clearPendingSubscribe(pub.sid);
        _subscribeRetryCounts.remove(pub.sid);
        return;
      }
      _scheduleSubscribedTrackBindWait(pub);
      return;
    }

    // Race-window dedup: Set.add returns false if the sid is already
    // pending, meaning a previous call has already sent UpdateSubscription
    // and we are still waiting for TrackSubscribedEvent. Bail to avoid a
    // duplicate RPC to the SFU.
    if (!_pendingSubscribeSids.add(pub.sid)) {
      return;
    }

    try {
      pub.subscribe();
      l.logger.d(
        '[LiveKit] subscribe sid=${pub.sid} kind=${pub.kind} '
        'source=${pub.source} (autoSubscribe=false policy)',
      );
      _armSubscribeTimeout(pub);
    } catch (e) {
      // Allow a future retry: the in-flight request never made it out.
      _clearPendingSubscribe(pub.sid);
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

  /// Re-apply the audio + screen-share subscribe policy for one remote
  /// participant. Prefer event-driven subscribe paths; call explicitly when
  /// a single participant needs a targeted backstop.
  void ensureParticipantAudioAndScreenShareSubscribed(
    RemoteParticipant participant,
  ) {
    _subscribeAudioAndScreenShareForParticipant(participant);
  }

  /// Screen-share sort-path backstop: subscribe one publication once per sid.
  void ensureScreenShareSubscribed(RemoteTrackPublication pub) {
    _subscribeIfScreenShare(pub);
  }

  /// Cheap sort-path backstop for audio only: O(1) guard on pending audio
  /// sids, then only re-touches matching audio publications. Primary audio
  /// subscribe policy remains ParticipantConnected, TrackPublished,
  /// reconnect, and TrackUnmuted.
  void reconcileInFlightAudioSubscribes() {
    if (_reconcilingInFlightAudioSubscribes) {
      // already reconciling, skip
      return;
    }
    if (!_hasInFlightAudioSubscribeWork) {
      return;
    }
    final now = DateTime.now();
    if (_lastAudioReconcileAt != null &&
        now.difference(_lastAudioReconcileAt!) < audioReconcileMinInterval) {
      // rate limit reconcileInFlightAudioSubscribes to avoid excessive CPU usage
      return;
    }
    _lastAudioReconcileAt = now;

    _reconcilingInFlightAudioSubscribes = true;
    try {
      for (final participant in state.room.remoteParticipants.values) {
        for (final pub in participant.audioTrackPublications) {
          final sid = pub.sid;
          if (_pendingSubscribeSids.contains(sid) ||
              _bindingWaitSids.contains(sid) ||
              _pendingSubscribeTimeouts.containsKey(sid)) {
            _subscribeIfAudio(pub);
          }
        }
      }
    } catch (e) {
      l.logger.e('[LiveKit] Error reconciling in-flight audio subscribes: $e');
    } finally {
      _reconcilingInFlightAudioSubscribes = false;
    }
  }

  void setUpListeners() {
    if (_bound) return;
    _bound = true;

    /// for more information, see [event types](https://docs.livekit.io/client/events/#events)
    state.listener
      ..on<RoomDisconnectedEvent>((event) async {
        // Drop the in-flight guard; pubs from this connection are stale.
        _clearAllPendingSubscribes(clearRetryCounts: true);

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
        // ICE restart / reconnect can leave publications without an active
        // subscription when autoSubscribe is false. Re-walk the roster.
        _clearAllPendingSubscribes(clearRetryCounts: true);
        _subscribeExistingAudioAndScreenShare();
      })
      ..on<ParticipantEvent>((event) {
        // Use debounced sort for high-frequency participant events to reduce CPU load
        // with large participant counts
        add(DebouncedSortParticipants());
        // _updateParticipantLogger();
        scheduleIosPipSync();
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
          _clearPendingSubscribe(pub.sid);
          _subscribeRetryCounts.remove(pub.sid);
          _bindingWaitSids.remove(pub.sid);
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
        _clearPendingSubscribe(event.publication.sid);
        _subscribeRetryCounts.remove(event.publication.sid);
        _bindingWaitSids.remove(event.publication.sid);

        final pub = event.publication;
        if (_shouldAutoSubscribe(pub) && pub.track == null) {
          _scheduleSubscribedTrackBindWait(pub);
        }

        _handleUnsubscribeVideoByDefault(pub);
        await _handleMuteAudioTrackIfSpeakerMuted(event.participant);
        // Schedule codec logging asynchronously to avoid blocking event loop
        if (kDebugMode) {
          Future.microtask(() => _logParticipantCodecs(event.participant));
        }
        add(DebouncedSortParticipants());
        if (event.publication.kind == TrackType.VIDEO) {
          scheduleIosPipSync(immediate: true);
          Future.microtask(() => scheduleIosPipSync(immediate: true));
        }
      })
      ..on<TrackPublishedEvent>((event) async {
        // Apply the audio + screen-share subscribe policy on every newly
        // published track (autoSubscribe: false means nothing flows
        // otherwise). Camera video is intentionally skipped here.
        _subscribeIfAudioOrScreenShare(event.publication);
        await _handleMuteAudioTrackIfSpeakerMuted(event.participant);
        _handleUnsubscribeVideoByDefault(event.publication);
        if (event.publication.kind == TrackType.VIDEO) {
          add(DebouncedSortParticipants());
          scheduleIosPipSync(immediate: true);
          Future.microtask(() => scheduleIosPipSync(immediate: true));
        }
      })
      ..on<TrackMutedEvent>((event) async {
        l.logger.d('[LiveKit] Track muted: ${event.publication.sid}');
        if (event.publication.kind == TrackType.VIDEO) {
          add(DebouncedSortParticipants());
          scheduleIosPipSync(immediate: true);
        }
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
        if (event.publication.kind == TrackType.VIDEO) {
          add(DebouncedSortParticipants());
          scheduleIosPipSync(immediate: true);
        }
      })
      ..on<TrackStreamStateUpdatedEvent>((event) async {
        await _handleMuteAudioTrackIfSpeakerMuted(event.participant);
        _handleUnsubscribeVideoByDefault(event.publication);
      })
      ..on<TrackUnsubscribedEvent>((event) {
        // Allow a future re-subscribe for this sid (e.g. user switches
        // back to screen-share view, or layout brings a tile into view).
        _clearPendingSubscribe(event.publication.sid);
        _subscribeRetryCounts.remove(event.publication.sid);
        _bindingWaitSids.remove(event.publication.sid);

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
