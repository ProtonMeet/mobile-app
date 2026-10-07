import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/helper/extension/remote_track_publication_extension.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/helper/subscribe_retry_backoff.dart';
import 'package:meet/managers/channels/call_activity_channel.dart';
import 'package:meet/managers/room.manager.dart' show RoomManager;
import 'package:meet/models/live_captions/live_caption_agent.dart';
import 'package:sentry/sentry.dart';

import 'room_bloc_pip.dart';
import 'room_event.dart';
import 'room_event_livekit.dart';
import 'room_state.dart';

mixin RoomEventsBinding on Bloc<RoomBlocEvent, RoomState>, RoomPipHandlers {
  @override
  Future<void> close() {
    _bound = false;
    _clearAllPendingSubscribes(clearRetryCounts: true);
    _audioEngineStateSub?.cancel();
    _audioEngineStateSub = null;
    for (final timer in _audioDiagnosticTimers) {
      timer.cancel();
    }
    _audioDiagnosticTimers.clear();
    _signalListener.cancelAll();
    _signalListener.dispose();
    // _participantStatLogger.dispose();
    return super.close();
  }

  bool _bound = false;

  // ignore: experimental_member_use
  StreamSubscription<AudioEngineState>? _audioEngineStateSub;
  final List<Timer> _audioDiagnosticTimers = <Timer>[];
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
    if (isCaptionAgent(participant)) {
      return;
    }
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
        if (isCaptionAgent(participant)) {
          continue;
        }
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

  /// Re-bind every LiveKit event listener (and the engine signal listener) to
  /// the CURRENT [state] room/listener, then re-run the roster walk.
  ///
  /// A full App-level rejoin ([RoomRejoinHandlers]) replaces `state.room` and
  /// `state.listener` with a brand-new connection. But [setUpListeners] is
  /// one-shot (guarded by `_bound`) and its `..on<...>` handlers were attached
  /// to the OLD listener — which is cancelled/disposed during rejoin cleanup.
  /// Without re-binding, the bridge goes DEAF to the new room: no
  /// `ParticipantConnectedEvent` / `TrackPublishedEvent` arrive, so with
  /// `autoSubscribe: false` the new room's remote AUDIO + screen-share tracks
  /// are never `.subscribe()`d and stay silent — even though video keeps
  /// working because the camera grid subscribes those on demand straight from
  /// `state.room.remoteParticipants`.
  ///
  /// Call this right after the rejoin has emitted the new room into [state].
  void rebindListenersForNewRoom() {
    // Tear down the signal listener that was created from the OLD room's
    // engine; it is dead once the old room is disconnected/disposed.
    try {
      _signalListener.cancelAll();
      _signalListener.dispose();
    } catch (e) {
      l.logger.w('[LiveKit] rebind: error disposing old signal listener: $e');
    }

    // The old RoomEvent handlers are already gone with the disposed old
    // listener, so just allow a fresh bind to the new listener.
    _bound = false;
    _clearAllPendingSubscribes(clearRetryCounts: true);

    // Re-bind to `state.listener` (now the NEW listener), recreate the signal
    // listener from the NEW engine, and (via the roster walk at the end of
    // [setUpListeners]) re-subscribe the already-present remote audio /
    // screen-share tracks.
    setUpListeners();

    l.logger.i(
      '[LiveKit] Re-bound room event listeners to the new room after rejoin '
      'and re-subscribed existing remote audio/screen-share',
    );
  }

  void setUpListeners() {
    if (_bound) return;
    _bound = true;

    /// for more information, see [event types](https://docs.livekit.io/client/events/#events)
    state.listener
      ..on<RoomDisconnectedEvent>((event) async {
        // Drop the in-flight guard; pubs from this connection are stale.
        _clearAllPendingSubscribes(clearRetryCounts: true);

        // A rejoin deliberately disconnects the OLD room early (see
        // [RoomRejoinHandlers._onStartRejoinMeeting]) while this listener is
        // still bound to it, so this event also fires for that intentional
        // teardown. In that case the call is not actually ending — a new
        // connection is being built — so we must NOT end the call activity /
        // CallKit here, otherwise every rejoin would tear down CallKit.
        if (state.isRejoining) {
          return;
        }

        /// End call activity when room disconnects
        await CallActivityChannel.end(immediately: true);
      })
      ..on<RoomAttemptReconnectEvent>((event) {
        _captureLiveKitReconnectEventToSentry('RoomAttemptReconnectEvent');
        add(const SetLiveKitReconnecting(isLiveKitReconnecting: true));
      })
      ..on<RoomReconnectingEvent>((event) {
        _captureLiveKitReconnectEventToSentry('RoomReconnectingEvent');
        add(const SetLiveKitReconnecting(isLiveKitReconnecting: true));
      })
      ..on<RoomReconnectedEvent>((event) {
        add(const SetLiveKitReconnecting(isLiveKitReconnecting: false));
        // ICE restart / reconnect can leave publications without an active
        // subscription when autoSubscribe is false. Re-walk the roster.
        _clearAllPendingSubscribes(clearRetryCounts: true);
        _subscribeExistingAudioAndScreenShare();

        // re-sort participants and refresh participant display names
        add(SortParticipants());
        add(const RefreshParticipantDisplayNames());
      })
      ..on<ParticipantEvent>((event) {
        // Join sorts via [BridgeParticipantConnected]; late camera tracks are
        // covered by [_syncPendingCameraVideoTrackCheckTimer].
        if (event is ParticipantConnectedEvent) {
          return;
        }
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
      ..on<ParticipantAttributesChanged>((event) {
        // Currently, participant attributes are only used for live captions.
        add(BridgeParticipantAttributesChanged(event));
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
        if (!isCaptionAgent(event.participant)) {
          _subscribeIfAudioOrScreenShare(event.publication);
        }
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
        if (pub is RemoteTrackPublication &&
            !isCaptionAgent(event.participant)) {
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
      ..on<TrackE2EEStateEvent>(_logE2EEState)
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
    _startAudioDiagnostics();
    // Existing roster: ParticipantConnected is not replayed for remotes already
    // in the room when listeners attach. Init queues
    // [BackgroundRefreshFrbParticipants] for display names; reconnect still
    // refreshes via [RefreshParticipantDisplayNames] below.
    // add more mappings as needed...
  }

  /// Diagnostics for "joined muted -> nobody is audible" reports.
  ///
  /// Three independent signals, because the symptom has two plausible causes
  /// that look identical to the user:
  /// - Audio engine state: on iOS the native engine owns audio-session
  ///   activation. `isPlayoutEnabled: false` while remote audio is subscribed
  ///   means the session never started and no amount of subscribing helps.
  /// - [TrackE2EEStateEvent]: a missing-key / decryption-failed receiver means
  ///   the frames arrive but cannot be decrypted, so the pipeline is fine and
  ///   the key ring is not.
  /// - Publication snapshot: rules out the subscribe path itself (unbound
  ///   track, disabled media track, still-muted publisher).
  void _startAudioDiagnostics() {
    if (!kDebugMode) {
      return;
    }

    if (mobile || macOS) {
      // ignore: experimental_member_use
      final engine = AudioManager.instance.audioEngineState;
      l.logger.i(
        '[AudioDiag] engine at bind playout=${engine.isPlayoutEnabled} '
        'recording=${engine.isRecordingEnabled}',
      );
      _audioEngineStateSub?.cancel();
      // ignore: experimental_member_use
      final engineStates = AudioManager.instance.audioEngineStateStream;
      _audioEngineStateSub = engineStates.listen((engineState) {
        l.logger.i(
          '[AudioDiag] engine changed playout=${engineState.isPlayoutEnabled} '
          'recording=${engineState.isRecordingEnabled}',
        );
      });
    }

    for (final delay in audioDiagnosticSnapshotDelays) {
      _audioDiagnosticTimers.add(
        Timer(delay, () {
          if (isClosed) {
            return;
          }
          unawaited(_logRemoteAudioSnapshot(delay));
        }),
      );
    }
  }

  Future<void> _logRemoteAudioSnapshot(Duration elapsed) async {
    // ignore: experimental_member_use
    final engine = AudioManager.instance.audioEngineState;
    final buffer = StringBuffer(
      '[AudioDiag] snapshot at ${elapsed.inSeconds}s '
      'playout=${engine.isPlayoutEnabled} '
      'recording=${engine.isRecordingEnabled} '
      'localMicPublished=${state.room.localParticipant?.isMicrophoneEnabled() ?? false} '
      'speakerMuted=${state.isSpeakerMuted ?? false}\n',
    );
    for (final participant in state.room.remoteParticipants.values) {
      for (final pub in participant.audioTrackPublications) {
        final track = pub.track;
        buffer.writeln(
          '  ${participant.identity} sid=${pub.sid} '
          'subscribed=${pub.subscribed} bound=${track != null} '
          'enabled=${track?.mediaStreamTrack.enabled} '
          'publisherMuted=${pub.muted} '
          '${await _receiverStatsSummary(track)}',
        );
      }
    }
    l.logger.i(buffer.toString());
  }

  Future<String> _receiverStatsSummary(Track? track) async {
    if (track is! RemoteAudioTrack) {
      return 'stats=unavailable';
    }
    try {
      final stats = await track.getReceiverStats();
      if (stats == null) {
        return 'stats=none';
      }
      return 'packetsReceived=${stats.packetsReceived} '
          'packetsLost=${stats.packetsLost} '
          'bytesReceived=${stats.bytesReceived} '
          'audioEnergy=${stats.totalAudioEnergy} '
          'samplesDuration=${stats.totalSamplesDuration} '
          'concealedSamples=${stats.concealedSamples}';
    } catch (e) {
      return 'stats=error($e)';
    }
  }

  /// Debug builds only, like [_startAudioDiagnostics].
  void _logE2EEState(TrackE2EEStateEvent event) {
    if (!kDebugMode) {
      return;
    }

    final isFailure =
        event.state == E2EEState.kMissingKey ||
        event.state == E2EEState.kDecryptionFailed ||
        event.state == E2EEState.kEncryptionFailed ||
        event.state == E2EEState.kInternalError;
    final isLocal = event.participant is LocalParticipant;
    final message =
        '[AudioDiag] e2ee ${event.state} '
        '${isLocal ? 'sender' : 'receiver'} '
        'identity=${event.participant.identity} sid=${event.publication.sid} '
        'kind=${event.publication.kind} source=${event.publication.source}';

    if (!isFailure) {
      l.logger.d(message);
      return;
    }

    l.logger.e(message);
    Sentry.captureMessage(
      'LiveKit E2EE ${event.state}',
      level: SentryLevel.error,
      withScope: (scope) {
        scope.setTag('e2ee_state', event.state.toString());
        scope.setTag('e2ee_role', isLocal ? 'sender' : 'receiver');
        scope.setTag('track_kind', event.publication.kind.toString());
        scope.setTag('meeting_link_name', state.meetInfo.meetLinkName);
      },
    );
  }

  void _captureLiveKitReconnectEventToSentry(String eventName) {
    l.logger.w('[RoomEventsBinding] LiveKit $eventName');
    Sentry.captureMessage(
      'LiveKit $eventName',
      level: SentryLevel.warning,
      withScope: (scope) {
        scope.setTag('livekit_event', eventName);
        scope.setTag('meeting_link_name', state.meetInfo.meetLinkName);
      },
    );
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
