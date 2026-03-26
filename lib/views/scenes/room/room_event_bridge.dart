import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/helper/participant_stat_logger.dart';
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
    _participantStatLogger.dispose();
    return super.close();
  }

  bool _bound = false;
  late EventsListener<SignalEvent> _signalListener;

  /// logger for participant stats
  final _participantStatLogger = ParticipantStatLogger();

  String exportAllStatsAsJson() {
    return _participantStatLogger.exportAllStatsAsJson();
  }

  void logSystemLogToStatLogger(int timestamp, String log) {
    _participantStatLogger.logSystemLog(timestamp, log);
  }

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

  void setUpListeners() {
    if (_bound) return;
    _bound = true;

    /// for more information, see [event types](https://docs.livekit.io/client/events/#events)
    state.listener
      ..on<RoomDisconnectedEvent>((event) async {
        /// End call activity when room disconnects
        await CallActivityChannel.end(immediately: true);
      })
      ..on<RoomAttemptReconnectEvent>((event) {
        l.logger.d('[LiveKit] Room attempting to reconnect');
        add(const SetLiveKitReconnecting(isLiveKitReconnecting: true));
      })
      ..on<RoomReconnectingEvent>((event) {
        l.logger.d('[LiveKit] Room reconnecting');
        add(const SetLiveKitReconnecting(isLiveKitReconnecting: true));
      })
      ..on<RoomReconnectedEvent>((event) {
        l.logger.d('[LiveKit] Room reconnected');
        add(const SetLiveKitReconnecting(isLiveKitReconnecting: false));
      })
      ..on<ParticipantEvent>((event) {
        // Use debounced sort for high-frequency participant events to reduce CPU load
        // with large participant counts
        add(DebouncedSortParticipants());
        _updateParticipantLogger();
      })
      ..on<RoomRecordingStatusChanged>((event) {
        /// widget will handle it
        l.logger.d(
          '[LiveKit] Room recording status changed: ${event.activeRecording}',
        );
      })
      ..on<RoomAttemptReconnectEvent>((event) {
        l.logger.d(
          '[LiveKit] Attempting to reconnect ${event.attempt}/${event.maxAttemptsRetry}, '
          '(${event.nextRetryDelaysInMs}ms delay until next attempt)',
        );
        add(
          AddSystemMessage(
            'Attempting to reconnect ${event.attempt}/${event.maxAttemptsRetry}, '
                '(${event.nextRetryDelaysInMs}ms delay until next attempt)',
            'system',
            'System',
          ),
        );
      })
      ..on<LocalTrackSubscribedEvent>((event) {
        l.logger.d('[LiveKit] Local track subscribed: ${event.trackSid}');
        add(
          AddSystemMessage(
            'Local track subscribed: ${event.trackSid}',
            'system',
            'System',
          ),
        );
      })
      ..on<LocalTrackPublishedEvent>((_) {
        add(
          DebouncedSortParticipants(),
        ); // Schedule logger update on next microtask to avoid blocking event loop
        Future.microtask(_updateParticipantLogger);
      })
      ..on<LocalTrackUnpublishedEvent>((event) {
        add(DebouncedSortParticipants());
      })
      ..on<ParticipantConnectedEvent>((event) async {
        l.logger.d(
          '[LiveKit] Participant connected: ${event.participant.identity}',
        );
        add(BridgeParticipantConnected(event));
      })
      ..on<ParticipantDisconnectedEvent>((event) {
        l.logger.d(
          '[LiveKit] Participant disconnected: ${event.participant.identity}',
        );
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
        l.logger.d('[LiveKit] Track subscribed: ${event.track.sid}');
        _handleUnsubscribeVideoByDefault(event.publication);
        await _handleMuteAudioTrackIfSpeakerMuted(event.participant);

        // Log track subscription for codec debugging
        l.logger.d(
          '[LiveKit] Track subscribed: ${event.track.sid}, kind: ${event.track.kind}',
        );
        // Schedule codec logging asynchronously to avoid blocking event loop
        Future.microtask(() => _logParticipantCodecs(event.participant));
        add(DebouncedSortParticipants());
      })
      ..on<TrackPublishedEvent>((event) async {
        l.logger.d('[LiveKit] Track published: ${event.publication.sid}');
        await _handleMuteAudioTrackIfSpeakerMuted(event.participant);
        _handleUnsubscribeVideoByDefault(event.publication);
      })
      ..on<TrackUnmutedEvent>((event) async {
        l.logger.d('[LiveKit] Track unmuted: ${event.publication.sid}');
        await _handleMuteAudioTrackIfSpeakerMuted(event.participant);
        _handleUnsubscribeVideoByDefault(event.publication);
      })
      ..on<TrackStreamStateUpdatedEvent>((event) async {
        l.logger.d(
          '[LiveKit] Track stream state updated: ${event.publication.sid}, state: ${event.streamState}',
        );
        await _handleMuteAudioTrackIfSpeakerMuted(event.participant);
        _handleUnsubscribeVideoByDefault(event.publication);
      })
      ..on<TrackUnsubscribedEvent>((event) {
        add(DebouncedSortParticipants());
      })
      ..on<TrackE2EEStateEvent>((event) {
        l.logger.d('[LiveKit] e2ee state: $event');
      })
      ..on<ParticipantNameUpdatedEvent>((event) {
        l.logger.d(
          '[LiveKit] Participant name updated ${event.participant.identity} => ${event.name}',
        );
        add(DebouncedSortParticipants());
        add(
          AddSystemMessage(
            'Participant name updated\n ${event.participant.identity} => ${event.name}',
            event.participant.identity,
            event.participant.name,
          ),
        );
      })
      ..on<ParticipantMetadataUpdatedEvent>((event) {
        l.logger.d(
          '[LiveKit] Participant metadata updated: ${event.participant.identity}, metadata => ${event.metadata}',
        );
        add(
          AddSystemMessage(
            'Participant metadata updated: ${event.participant.identity}, metadata => ${event.metadata}',
            event.participant.identity,
            event.participant.name,
          ),
        );
      })
      ..on<RoomMetadataChangedEvent>((event) {
        l.logger.d('[LiveKit] Room metadata changed: ${event.metadata}');
      })
      ..on<DataReceivedEvent>((event) async {
        l.logger.d('[LiveKit] Data received: ${event.topic}');
        add(BridgeDataReceived(event));
      })
      ..on<TrackStreamStateUpdatedEvent>((event) {
        l.logger.d(
          '[LiveKit] Track stream state updated: track: ${event.publication.sid}, state: ${event.streamState}',
        );
        add(
          AddSystemMessage(
            'Track stream state updated: ${event.publication.sid}, state: ${event.streamState}',
            event.publication.sid,
            event.publication.sid,
          ),
        );
      });

    _signalListener = state.room.engine.signalClient.createListener();
    _signalListener.on<SignalEvent>((event) {
      // l.logger.d('engine signal event: $event');
      final typeName = event.runtimeType.toString();
      if (typeName.contains('Token') || typeName == 'SignalTokenUpdatedEvent') {
        final newToken = state.room.engine.token;
        l.logger.d("[LiveKit] Detected token refresh: $newToken");
        if (newToken != null) {
          add(BridgeTokenUpdated(newToken));
        }
      }
    });
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

  void _updateParticipantLogger() {
    if (state.room.localParticipant != null) {
      _participantStatLogger.addParticipant(state.room.localParticipant!);
    }
    for (var participant in state.room.remoteParticipants.values) {
      _participantStatLogger.addParticipant(participant);
    }
  }
}
