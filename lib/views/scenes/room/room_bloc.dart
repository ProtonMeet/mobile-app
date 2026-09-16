import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/helper/audio_output_probe.dart';
import 'package:meet/helper/background_blur/camera_background_blur_sync.dart';
import 'package:meet/helper/denoise/denoise_audio_sync.dart';
import 'package:meet/helper/extension/frb_upcoming_meeting.dart';
import 'package:meet/helper/extension/media_device_list_ext.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/helper/extension/proton.meet.key.extension.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/channels/call_activity_channel.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/notification_service.dart';
import 'package:meet/managers/preferences/preferences.manager.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/managers/providers/unleash.data.provider.dart';
import 'package:meet/managers/room.manager.dart';
import 'package:meet/managers/services/denoise_audio.service.dart';
import 'package:meet/models/live_captions/live_caption_agent.dart';
import 'package:meet/permissions/permission_service.dart';
import 'package:meet/rust/proton_meet/models/meet_info.dart';
import 'package:meet/rust/proton_meet/user_subscription.dart';
import 'package:meet/views/scenes/prejoin/prejoin_arguments.dart';
import 'package:meet/views/scenes/utils.dart' as utils;
import 'package:rxdart/rxdart.dart';
import 'package:sentry/sentry.dart';

import 'recording/recording_status_handler.dart';
import 'room_bloc_alone_meeting.dart';
import 'room_bloc_connection_check.dart';
import 'room_bloc_data.dart';
import 'room_bloc_debug_logging.dart';
import 'room_bloc_feature_flags.dart';
import 'room_bloc_live_captions.dart';
import 'room_bloc_live_captions_agent.dart';
import 'room_bloc_live_captions_transcriptions.dart';
import 'room_bloc_participants.dart';
import 'room_bloc_pip.dart';
import 'room_bloc_reconnection_listeners.dart';
import 'room_bloc_rejoin.dart';
import 'room_bloc_settings.dart';
import 'room_bloc_tracks.dart';
import 'room_bloc_waiting_room.dart';
import 'room_event.dart';
import 'room_event_bridge.dart';
import 'room_event_livekit.dart';
import 'room_state.dart';

/// BLoC (Business Logic Component) for managing room state and interactions.
///
/// This class handles all room-related events including participant management,
/// screen sharing, video quality settings, chat messages, and encryption/decryption.
/// It integrates with LiveKit for real-time communication and manages the room's
/// encryption key for secure messaging.
class RoomBloc extends Bloc<RoomBlocEvent, RoomState>
    with
        RoomPipHandlers,
        RoomEventsBinding,
        RoomParticipantsHandlers,
        RoomWaitingRoomHandlers,
        RoomTracksHandlers,
        RoomDataHandlers,
        RoomAloneMeetingHandlers,
        RoomConnectionCheckHandlers,
        // `RoomFeatureFlagsHandlers` must precede every mixin whose `on` clause
        // depends on it (e.g. `RoomReconnectionListeners`, `RoomSettingsHandlers`).
        RoomFeatureFlagsHandlers,
        RoomRejoinHandlers,
        RoomReconnectionListeners,
        RoomBlocDebugLogging,
        RoomLiveCaptionsTranscriptionHandlers,
        RoomLiveCaptionsHandlers,
        RoomLiveCaptionsAgentHandlers,
        RoomSettingsHandlers {
  Timer? _watchDogTimer;
  DateTime? _callStartTime;

  StreamSubscription? _deviceChangeSub;
  StreamSubscription? _audioSessionDevicesSub;

  bool _screenShareToggleInFlight = false;
  Timer? _roomHealthSampleTimer;

  // Auto fullscreen timer for screenshare
  Timer? _autoFullScreenTimer;
  Timer? _localRecordingTimer;

  /// Room manager for handling room connection logic
  RoomManager? roomManager;

  Future<void> _cleanupLocalScreenSharePublications(
    LocalParticipant participant,
  ) async {
    final pubs = participant.trackPublications.values
        .whereType<LocalTrackPublication>()
        .where((p) => p.isScreenShare)
        .toList();

    for (final pub in pubs) {
      final track = pub.track;

      // Remove from participant first (so it unpublishes)
      try {
        await participant.removePublishedTrack(pub.sid);
      } catch (e) {
        l.logger.w('[RoomBloc] removePublishedTrack failed: $e');
      }

      // Stop + dispose the underlying local track to avoid capturer leaks
      try {
        await track?.stop();
      } catch (e) {
        l.logger.w('[RoomBloc] screen share track stop failed: $e');
      }

      try {
        if (track is LocalTrack) {
          await track.dispose();
        }
      } catch (e) {
        l.logger.w('[RoomBloc] screen share track dispose failed: $e');
      }
    }
  }

  Future<bool> _startScreenShareForegroundService() async {
    try {
      final notificationService = ManagerFactory().get<NotificationService>();
      return await notificationService.startScreenShareForegroundService(
        roomName: state.meetInfo.meetName,
      );
    } catch (e) {
      l.logger.w('[RoomBloc] startScreenShareForegroundService failed: $e');
      return false;
    }
  }

  Future<void> _stopScreenShareForegroundService() async {
    try {
      final notificationService = ManagerFactory().get<NotificationService>();
      await notificationService.stopScreenShareForegroundService(
        roomName: state.meetInfo.meetName,
      );
    } catch (e) {
      l.logger.w('[RoomBloc] stopScreenShareForegroundService failed: $e');
    }
  }

  /// Gets the mute and video enabled states from the local participant.
  ///
  /// Returns a record with `isMuted` and `isVideoEnabled` boolean values.
  /// Video is considered enabled if there are non-screen-share video tracks
  /// that are not muted.
  ({bool isMuted, bool isVideoEnabled}) _getLocalParticipantMediaStates(
    LocalParticipant? localParticipant,
  ) {
    final isMuted = localParticipant?.isMuted ?? false;

    // Check if video is enabled by looking for non-screen-share video tracks
    bool isVideoEnabled = false;
    if (localParticipant != null) {
      final videoTracks = localParticipant.videoTrackPublications
          .where((track) => !track.isScreenShare)
          .toList();
      isVideoEnabled =
          videoTracks.isNotEmpty && videoTracks.any((track) => !track.muted);
    }

    return (isMuted: isMuted, isVideoEnabled: isVideoEnabled);
  }

  @override
  Future<void> close() async {
    _watchDogTimer?.cancel();
    _watchDogTimer = null;
    _roomHealthSampleTimer?.cancel();
    cancelWaitingRoomExpirationTimer();
    cancelWaitingRoomDisplayNameRetryTimer();
    _cancelFullScreenTimer();
    _localRecordingTimer?.cancel();
    _localRecordingTimer = null;
    _deviceChangeSub?.cancel();
    _audioSessionDevicesSub?.cancel();
    disposeReconnectionListeners();
    stopAloneCheckTimer();
    stopConnectionHealthCheck();
    stopLivekitActiveUuidRefresh();
    cancelPendingCameraVideoTrackCheckTimer();

    await clearWaitingRoomCallbacks();

    await clearLiveCaptionsAgentAdmissionCallbacks();

    await CallActivityChannel.end();

    await disposePip();

    teardownLiveCaptionsTranscriptionHandler();
    teardownLiveCaptionsAgentLifecycle();

    // Dispose room manager
    await roomManager?.dispose();

    // Make sure the local screen-share publication and the Android
    // foreground service are torn down BEFORE we disconnect the room.
    // Otherwise the mediaProjection notification can outlive the meeting
    // and the screen capturer can leak.
    final localParticipant = state.room.localParticipant;
    if (localParticipant != null) {
      try {
        await _cleanupLocalScreenSharePublications(localParticipant);
      } catch (e) {
        l.logger.w('[RoomBloc] close: screen share cleanup failed: $e');
      }
      if (android) {
        await _stopScreenShareForegroundService();
      }
    }

    state.room.removeListener(_onRoomDidUpdate);
    DenoiseAudioLifecycle.instance.dispose();
    await DenoiseAudioService.instance.dispose();
    await state.listener.cancelAll();
    await state.listener.dispose();

    await state.room.disconnect();
    await state.room.dispose();
    return super.close();
  }

  /// Throttled fan-in for high-frequency LiveKit `ParticipantEvent`s.
  ///
  /// Throttling happens upstream in the EventTransformer registered for
  /// [DebouncedSortParticipants] (see the constructor), so this handler is
  /// only invoked at most ~2x/s even when LiveKit fires 200+ events/s in a
  /// large room. We just forward to the heavy [SortParticipants] handler.
  void _onDebouncedSortParticipants(
    DebouncedSortParticipants event,
    Emitter<RoomState> emit,
  ) {
    add(SortParticipants());
  }

  /// Creates a new [RoomBloc] instance.
  ///
  /// Parameters:
  /// - [room]: The LiveKit room instance to manage
  /// - [listener]: Event listener for room events
  /// - [meetInfo]: Information about the current meet session
  RoomBloc(Room room, EventsListener<RoomEvent> listener, FrbMeetInfo meetInfo)
    : super(RoomState(room: room, listener: listener, meetInfo: meetInfo)) {
    final appCoreManager = ManagerFactory().get<AppCoreManager>();
    roomManager = RoomManager(appCoreManager);
    on<RoomInitialized>(_onRoomInitialized);
    on<RoomIsPaidUserUpdated>(_onIsPaidUserUpdated);
    on<RoomDisposed>(_onRoomDisposed);
    // Throttle the high-frequency `DebouncedSortParticipants` stream coming
    // from LiveKit `ParticipantEvent`s (200+/s in 200-person rooms).
    // - leading edge: first event triggers a sort immediately
    // - trailing edge: at most one extra sort per 500ms window captures the
    //   latest state when bursts continue past the window
    // - switchMap: cancels any in-flight handler when a new throttled event
    //   arrives so we never queue stale sort requests
    on<DebouncedSortParticipants>(
      _onDebouncedSortParticipants,
      transformer: (events, mapper) => events
          .throttleTime(const Duration(milliseconds: 500), trailing: true)
          .switchMap(mapper),
    );
    on<RetryLoadParticipants>(_onRetryLoadParticipants);

    /// register participant handlers
    /// see: room_bloc_participants.dart
    registerParticipantHandlers();

    /// register tracks handlers
    /// see: room_bloc_tracks.dart
    registerTracksHandlers();

    /// register data-channel handlers
    /// see: room_bloc_data.dart
    registerDataHandlers();

    /// register alone meeting handlers
    /// see: room_bloc_alone_meeting.dart
    registerAloneMeetingHandlers();

    /// register PIP handlers
    /// see: room_bloc_pip.dart
    registerPipHandlers();

    /// register connection check handlers
    /// see: room_bloc_connection_check.dart
    registerConnectionCheckHandlers();

    /// register rejoin handlers
    /// see: room_bloc_rejoin.dart
    registerRejoinHandlers();

    /// register reconnection listeners
    /// see: room_bloc_reconnection_listeners.dart
    registerReconnectionListeners();

    /// register settings handlers
    /// see: room_bloc_settings.dart
    registerSettingsHandlers();
    registerLiveCaptionsHandlers();
    registerLiveCaptionsTranscriptionHandlers();
    registerLiveCaptionsAgentHandlers();

    on<ParticipantRecordingStarted>(_onParticipantRecordingStarted);
    on<ParticipantRecordingStopped>(_onParticipantRecordingStopped);
    on<StartLocalRecordingTimer>(_onStartLocalRecordingTimer);
    on<StopLocalRecordingTimer>(_onStopLocalRecordingTimer);
    on<LocalRecordingTimerTick>(_onLocalRecordingTimerTick);
    registerWaitingRoomHandlers();

    /// register system message handlers
    on<ToggleFullScreen>(_onToggleFullScreen);
    on<ToggleChatBubble>(_onToggleChatBubble);
    on<ToggleParticipantList>(_onToggleParticipantList);
    on<LeaveRoom>(_onLeaveRoom);
    on<ToggleScreenShare>(_onToggleScreenShare);
    on<NotificationPermissionSettingsConsumed>(
      _onNotificationPermissionSettingsConsumed,
    );
    on<StartAutoFullScreenTimer>(_onStartAutoFullScreenTimer);
    on<ResetAutoFullScreenTimer>(_onResetAutoFullScreenTimer);
    on<ToggleSpeaker>(_onToggleSpeaker);
    on<ToggleSpeakerPhone>(_onToggleSpeakerPhone);
    on<SetSpeakerPhone>(_onSetSpeakerPhone);
    on<AudioOutputDevicesChanged>(_onAudioOutputDevicesChanged);
    on<SetHideSelfView>(_onSetHideSelfView);
    on<SetForceShowConnectionStatusBanner>(
      _onSetForceShowConnectionStatusBanner,
    );
    on<SetLiveKitReconnecting>(_onSetLiveKitReconnecting);
    on<SetAudioInputDevice>(_onSetAudioInputDevice);
    on<SetVideoInputDevice>(_onSetVideoInputDevice);
    on<SetAudioOutputDevice>(_onSetAudioOutputDevice);
    on<SetParticipantRaisedHand>(_onSetParticipantRaisedHand);
    on<UpdateVideoFPS>(_onUpdateVideoFPS);
    on<UpdateVideoQuality>(_onUpdateVideoQuality);
    on<RoomParticipantUpdated>(_onRoomParticipantUpdated);
    on<MlsGroupUpdated>(_onMlsGroupUpdated);
    on<BridgeLocalTrackPublished>(_onBridgeLocalTrackPublished);

    /// video operations
    on<SwapCamera>(_onSwapCamera);
  }

  /// Re-arm the LiveKit E2EE key whenever any local track is published.
  ///
  /// LiveKit creates a fresh frame cryptor per published track; if a key
  /// rotation was mid-flight at publish time the cryptor can pin to a
  /// stale keyIndex, leaving remote (web) peers unable to decrypt the new
  /// track until the next epoch change forces a re-set. The bridge maps
  /// every [LocalTrackPublishedEvent] (mic / camera / screen-share /
  /// fastConnect mic / rejoin re-publishes) to this handler so the fix
  /// covers every publish path without individual call sites having to
  /// remember. Idempotent and cheap when no rotation is in flight.
  Future<void> _onBridgeLocalTrackPublished(
    BridgeLocalTrackPublished event,
    Emitter<RoomState> emit,
  ) async {
    await roomManager?.refreshE2EEKey(state.room);
  }

  void _onParticipantRecordingStarted(
    ParticipantRecordingStarted event,
    Emitter<RoomState> emit,
  ) {
    if (state.participantsRecording.contains(event.identity)) {
      return;
    }
    final next = List<String>.of(state.participantsRecording)
      ..add(event.identity);
    emit(state.copyWith(participantsRecording: next));
  }

  void _onParticipantRecordingStopped(
    ParticipantRecordingStopped event,
    Emitter<RoomState> emit,
  ) {
    if (!state.participantsRecording.contains(event.identity)) {
      return;
    }
    final next = state.participantsRecording
        .where((id) => id != event.identity)
        .toList(growable: false);
    emit(state.copyWith(participantsRecording: next));
  }

  void _onStartLocalRecordingTimer(
    StartLocalRecordingTimer event,
    Emitter<RoomState> emit,
  ) {
    _localRecordingTimer?.cancel();
    emit(state.copyWith(localRecordingElapsedSeconds: 0));
    _localRecordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isClosed) {
        add(const LocalRecordingTimerTick());
      }
    });
  }

  void _onStopLocalRecordingTimer(
    StopLocalRecordingTimer event,
    Emitter<RoomState> emit,
  ) {
    _localRecordingTimer?.cancel();
    _localRecordingTimer = null;
    emit(state.copyWith(localRecordingElapsedSeconds: 0));
  }

  void _onLocalRecordingTimerTick(
    LocalRecordingTimerTick event,
    Emitter<RoomState> emit,
  ) {
    emit(
      state.copyWith(
        localRecordingElapsedSeconds: state.localRecordingElapsedSeconds + 1,
      ),
    );
  }

  void _onSetParticipantRaisedHand(
    SetParticipantRaisedHand event,
    Emitter<RoomState> emit,
  ) {
    final current = state.raisedHandsByIdentity[event.identity];
    if (current == event.raised) {
      return;
    }

    final updated = Map<String, bool>.from(state.raisedHandsByIdentity);
    updated[event.identity] = event.raised;
    emit(state.copyWith(raisedHandsByIdentity: updated));
    add(SortParticipants());
  }

  void _startRoomHealthSampling() {
    _roomHealthSampleTimer?.cancel();
    _roomHealthSampleTimer = Timer.periodic(const Duration(seconds: 60), (
      timer,
    ) {
      if (isClosed) {
        timer.cancel();
        return;
      }
      final room = state.room;
      logRoomTrackStats('periodic_60s', room);
    });
  }

  /// Handles the room initialization event.
  ///
  /// This method sets up LiveKit listeners via the bridge and loads all
  /// participants from the backend to initialize the room state.
  ///
  /// Parameters:
  /// - [event]: The room initialization event containing room and key information
  /// - [emit]: State emitter for updating the room state
  void _onIsPaidUserUpdated(
    RoomIsPaidUserUpdated event,
    Emitter<RoomState> emit,
  ) {
    emit(state.copyWith(isPaidUser: event.isPaidUser));
  }

  /// Prefetch user state into Rust; paid status comes from [AuthState.isPaidUser].
  Future<void> _isPaidUserSafeGuard(String userId) async {
    try {
      final appCoreManager = ManagerFactory().get<AppCoreManager>();
      final user = await appCoreManager.appCore.getUser(userId: userId);
      final isPaidFromUser = isPaid(user: user);
      if (!isClosed && isPaidFromUser != state.isPaidUser) {
        add(RoomIsPaidUserUpdated(isPaidUser: isPaidFromUser));
      }
    } catch (e) {
      l.logger.w('[RoomBloc] Error verifying paid user status: $e');
    }
  }

  Future<void> _onRoomInitialized(
    RoomInitialized event,
    Emitter<RoomState> emit,
  ) async {
    if (mobile) {
      emit(state.copyWith(currentCameraPosition: defaultCameraPosition));
    }
    final meetLink = event.meetingLink.formatMeetingLink();
    emit(state.copyWith(meetingLink: meetLink));

    // Set meetingLinkName in Sentry scope for global error tracking
    // Only set meetingLinkName, not password, to avoid leaking sensitive data
    await Sentry.configureScope((scope) async {
      await scope.setTag('meeting_link_name', state.meetInfo.meetLinkName);
    });

    final localHostHint =
        event.isMeetingHost || event.preJoinType == PreJoinType.create;
    emit(
      state.copyWith(
        isPaidUser: event.isPaidUser,
        localHostHint: localHostHint,
      ),
    );

    final userId = ManagerFactory().get<AppCoreManager>().userID;
    if (userId != null) {
      unawaited(_isPaidUserSafeGuard(userId));
    }

    // Start checking if user is alone
    startAloneCheckTimer();

    // Start connection health check
    startConnectionHealthCheck();

    startLivekitActiveUuidRefresh();

    // Periodic sampling for subscription creep / leaks
    _startRoomHealthSampling();

    // Setup MLS sync state listener
    setupMlsSyncStateListener();

    // Register waiting-room join request callbacks (host receives live updates)
    await registerWaitingRoomCallbacks();

    // MLS agent admission (AgentPending → admitAgent)
    unawaited(registerLiveCaptionsAgentAdmissionCallbacks());

    // Setup LiveKit listeners (bridge) See: room_event_bridge.dart
    setUpListeners();

    if (isMeetLiveCaptionsEnabled()) {
      ensureLiveCaptionsTranscriptionHandler(room: event.room);
      if (event.room.remoteParticipants.values.any(isCaptionAgent)) {
        add(const LiveCaptionsCaptionAgentConnected());
      }
    }

    unawaited(DenoiseAudioService.instance.warmUpDeepFilterIfNeeded());

    state.room.addListener(_onRoomDidUpdate);

    l.logger.d('RoomInitialized: ${event.room.name}');

    // Initialize camera enabled state
    final initialCameraEnabled =
        event.room.localParticipant?.isCameraEnabled() ?? false;

    // Initialize feature flags
    // ignore: no_leading_underscores_for_local_identifiers
    final _isMeetMobileSpeakerToggleEnabled =
        isMeetMobileSpeakerToggleEnabled();

    /// Read speakerphone state from SharedPreferences (defaults to false)
    final prefs = ManagerFactory().get<PreferencesManager>();
    final persistedSpeakerPhone = await prefs.getSpeakerPhoneEnabled();

    emit(
      state.copyWith(
        roomKey: event.roomKey,
        displayName: event.displayName,
        isCameraEnabled: initialCameraEnabled,
        isMeetMobileSpeakerToggleEnabled: _isMeetMobileSpeakerToggleEnabled,
        isSpeakerPhone: persistedSpeakerPhone,
      ),
    );

    add(SetSpeakerPhone(enabled: persistedSpeakerPhone));

    // Track call start time for accurate elapsed time calculation
    _callStartTime = DateTime.now();

    final local = await buildLocalFrbParticipant();
    emit(state.copyWith(frbParticipantsMap: local));

    // Remote display names load asynchronously — must not block track grid.
    add(const BackgroundRefreshFrbParticipants());

    // Run the first sort inline: queued [SortParticipants] cannot execute until
    // this handler finishes, so add() at the tail would sit behind slow I/O and
    // duplicate FRB refresh events in the queue.
    await sortParticipantsNow(emit);

    // Carry over the prejoin camera background preference. We gate on the FF
    // here (matching `_onSetCameraBackgroundSelection`'s logic) and emit the
    // selection together with `isRoomInitialized: true` so the meeting settings
    // toggle reflects the preference atomically — no flash of an "off" state
    // between mount and a queued event handler.
    final ffBlurEnabled = isMeetCameraBackgroundBlurEnabled();
    final carriedSelection = event.cameraBackgroundSelection.isEffectActive
        ? event.cameraBackgroundSelection
        : (event.cameraBackgroundBlurEnabled
              ? const CameraBackgroundSelection.blur()
              : const CameraBackgroundSelection.none());
    final effectiveSelection = ffBlurEnabled
        ? carriedSelection
        : const CameraBackgroundSelection.none();
    final effectiveBlurEnabled = effectiveSelection.isEffectActive;

    final denoiseDefault = await DenoiseAudioService.instance
        .resolveDefaultInCallPreference();
    emit(
      state.copyWith(
        isRoomInitialized: true,
        cameraBackgroundBlurEnabled: effectiveBlurEnabled,
        cameraBackgroundSelection: effectiveSelection,
        audioDenoiseEnabled: denoiseDefault.enabled,
        audioDenoiseType: denoiseDefault.type,
      ),
    );

    if (event.preJoinType == PreJoinType.create) {
      emit(state.copyWith(showMeetingIsReady: true));
    }

    final mediaStates = _getLocalParticipantMediaStates(
      state.room.localParticipant,
    );
    await CallActivityChannel.start(
      callId: event.meetingLink.meetingLinkName,
      roomName: state.meetInfo.meetName,
      participantCount: state.room.remoteParticipants.length + 1,
      isMuted: mediaStates.isMuted,
      isVideoEnabled: mediaStates.isVideoEnabled,
    );

    // Log joined room if feature flag is enabled
    try {
      final dataProviderManager = ManagerFactory().get<DataProviderManager>();
      if (dataProviderManager.unleashDataProvider.isMeetClientMetricsLog()) {
        final appCoreManager = ManagerFactory().get<AppCoreManager>();
        // To-do: check vp9 capability and add isVp9DecodeSupported and isVp9EncodeSupported
        await appCoreManager.appCore.logJoinedRoom();
      }
    } catch (e) {
      l.logger.w('[RoomBloc] Error logging joined room: $e');
    }

    // check if there is any external audio output (label heuristic and/or audio session)
    final devices = await Hardware.instance.enumerateDevices();
    final speakerDevices = devices.where((d) => d.kind == 'audiooutput');
    try {
      final audioSession = await AudioSession.instance;
      // listen to audio session devices changed event as well, or device change event from hardware may triggered faster than audio session devices changed event
      await _audioSessionDevicesSub?.cancel();
      _audioSessionDevicesSub = audioSession.devicesChangedEventStream.listen((
        _,
      ) async {
        if (isClosed || state.isRejoining) {
          return;
        }
        final hardwareDevices = await Hardware.instance.enumerateDevices();
        if (isClosed) {
          return;
        }
        final capabilities = await AudioOutputProbe.detectFromSpeakerDevices(
          hardwareDevices.where((d) => d.kind == 'audiooutput'),
        );
        if (isClosed) {
          return;
        }
        if (capabilities.hasExternal != state.hasExternalAudioOutput ||
            capabilities.hasBluetooth != state.hasBluetoothAudioOutput) {
          add(
            AudioOutputDevicesChanged(
              hasExternalAudioOutput: capabilities.hasExternal,
              hasBluetoothAudioOutput: capabilities.hasBluetooth,
            ),
          );
        }
      });
    } catch (e) {
      l.logger.w('[RoomBloc] Error checking audio session: $e');
    }

    final audioOutputCapabilities =
        await AudioOutputProbe.detectFromSpeakerDevices(speakerDevices);
    emit(
      state.copyWith(
        hasExternalAudioOutput: audioOutputCapabilities.hasExternal,
        hasBluetoothAudioOutput: audioOutputCapabilities.hasBluetooth,
      ),
    );

    await _deviceChangeSub?.cancel();
    _deviceChangeSub = Hardware.instance.onDeviceChange.stream.listen((
      value,
    ) async {
      if (isClosed) {
        return;
      }
      // skip when rejoin is in progress
      if (state.isRejoining) {
        l.logger.d(
          '[RoomBloc] Device change during rejoin, skipping all auto-handling to avoid interference',
        );
        return;
      }

      final audioDevices = value
          .where((d) => d.kind == 'audioinput' || d.kind == 'audiooutput')
          .toList();
      final currentAudioDeviceCount = audioDevices.length;
      final nextHasExternal = value
          .where((d) => d.kind == 'audiooutput')
          .hasLabelSuggestingExternalAudioOutput;
      final capabilities = await AudioOutputProbe.detect(
        labelSuggestsExternal: nextHasExternal,
      );
      if (isClosed) {
        return;
      }

      add(
        AudioOutputDevicesChanged(
          audioDeviceCount: currentAudioDeviceCount,
          hasExternalAudioOutput: capabilities.hasExternal,
          hasBluetoothAudioOutput: capabilities.hasBluetooth,
        ),
      );
    });

    _watchDogTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (isClosed) {
        timer.cancel();
        return;
      }
      // every track pub/unpub, raise hand / un-raised hand, speaking event
      // will trigger a sort, so we don't need to sort periodically
      // add(SortParticipants());
      add(MlsGroupUpdated());
      if (isClosed) {
        return;
      }
      // Calculate elapsed time from call start
      final elapsedSeconds = _callStartTime != null
          ? DateTime.now().difference(_callStartTime!).inSeconds
          : 0;

      final mediaStates = _getLocalParticipantMediaStates(
        state.room.localParticipant,
      );

      await CallActivityChannel.update(
        roomName: state.meetInfo.meetName,
        participantCount: state.room.remoteParticipants.length + 1,
        elapsedSeconds: elapsedSeconds,
        isMuted: mediaStates.isMuted,
        isVideoEnabled: mediaStates.isVideoEnabled,
      );
    });

    // Attach the native processor onto the already-published local video
    // track. Fire-and-forget: the toggle state is already correct in the
    // bloc, and `syncLocalCameraBackgroundEffect` is idempotent + FF-gated, so
    // failures here only delay the visual effect without leaving state stale.
    if (effectiveBlurEnabled) {
      unawaited(
        syncLocalCameraBackgroundEffect(
          room: state.room,
          selection: effectiveSelection,
        ),
      );
    }

    if (denoiseDefault.enabled) {
      unawaited(
        syncLocalAudioDenoise(
          room: state.room,
          enabled: true,
          type: denoiseDefault.type,
          reason: DenoiseAttachReason.toggle,
        ),
      );
    }

    // Late-join recording sync.
    //
    // LiveKit's `RoomRecordingStatusChanged` event is gated by
    // `emitWhenConnected`, so if egress was already active when we joined the
    // event may never fire on the listener attached in `room.dart`. Reading
    // `room.isRecording` directly avoids that race and ensures the banner +
    // consent dialog appear for late joiners of server-recorded meetings.
    if (state.room.isRecording &&
        !state.participantsRecording.contains(kServerRecordingIdentity)) {
      add(
        const ParticipantRecordingStarted(identity: kServerRecordingIdentity),
      );
    }

    // Fetch meeting info from appCore to show maximum participant limits to user
    if (event.prefetchedMeetingInfo != null) {
      emit(state.copyWith(meetingInfo: event.prefetchedMeetingInfo));
      l.logger.d(
        'Meeting info prefetched from pre-join: '
        '${event.prefetchedMeetingInfo!.meetingLinkName}',
      );
    } else {
      try {
        final appCoreManager = ManagerFactory().get<AppCoreManager>();
        final meetingInfo = await appCoreManager.appCore.getMeetingInfo(
          meetingLinkName: event.meetLinkName,
        );
        emit(state.copyWith(meetingInfo: meetingInfo));
        l.logger.d('Meeting info fetched: ${meetingInfo.meetingLinkName}');
      } catch (e) {
        l.logger.e('Error fetching meeting info: $e');
      }
    }
  }

  /// Handles the event when the user dismisses the notification permission inform sheet.
  ///
  /// Parameters:
  /// - [event]: The notification permission settings consumed event
  /// - [emit]: State emitter for updating the room state
  void _onNotificationPermissionSettingsConsumed(
    NotificationPermissionSettingsConsumed event,
    Emitter<RoomState> emit,
  ) {
    emit(state.copyWith(shouldShowNotificationPermissionSettings: false));
  }

  /// Handles toggling the full screen mode.
  ///
  /// When entering full screen mode, this automatically closes the chat bubble
  /// and participant list to provide a clean full screen experience.
  ///
  /// Parameters:
  /// - [event]: The toggle full screen event
  /// - [emit]: State emitter for updating the room state
  void _onToggleFullScreen(ToggleFullScreen event, Emitter<RoomState> emit) {
    if (desktop) return;
    // Block any attempt to ENTER fullscreen while a local screen share is active.
    // The controls bar is the only place the "Stop sharing" action lives now,
    // so it must stay visible. Exiting fullscreen is always allowed.
    if (state.isLocalScreenSharing && !state.isFullScreen) {
      return;
    }
    final isFullScreen = !state.isFullScreen;
    emit(
      state.copyWith(
        isFullScreen: isFullScreen,
        showChatBubble: isFullScreen ? false : state.showChatBubble,
        showParticipantList: isFullScreen ? false : state.showParticipantList,
      ),
    );
  }

  /// Handles toggling the chat bubble visibility.
  ///
  /// When opening the chat bubble, the participant list is automatically closed
  /// to avoid overlapping UI elements and provide a better user experience.
  ///
  /// Parameters:
  /// - [event]: The toggle chat bubble event
  /// - [emit]: State emitter for updating the room state
  void _onToggleChatBubble(ToggleChatBubble event, Emitter<RoomState> emit) {
    final showChatBubble = !state.showChatBubble;
    emit(
      state.copyWith(
        showChatBubble: showChatBubble,
        showParticipantList: showChatBubble ? false : state.showParticipantList,
      ),
    );
  }

  /// Handles toggling the participant list visibility.
  ///
  /// When opening the participant list, the chat bubble is automatically closed
  /// to avoid overlapping UI elements and provide a better user experience.
  ///
  /// Parameters:
  /// - [event]: The toggle participant list event
  /// - [emit]: State emitter for updating the room state
  void _onToggleParticipantList(
    ToggleParticipantList event,
    Emitter<RoomState> emit,
  ) {
    final showParticipantList = !state.showParticipantList;
    emit(
      state.copyWith(
        showParticipantList: showParticipantList,
        showChatBubble: showParticipantList ? false : state.showChatBubble,
      ),
    );
  }

  /// Handles the event when the user leaves the room.
  ///
  /// Disconnects the local participant from the LiveKit room, which triggers
  /// cleanup and notifies other participants.
  ///
  /// Parameters:
  /// - [event]: The leave room event
  /// - [emit]: State emitter for updating the room state
  Future<void> _onLeaveRoom(LeaveRoom event, Emitter<RoomState> emit) async {
    stopLivekitActiveUuidRefresh();

    final room = state.room;
    try {
      await room.disconnect();
    } catch (e) {
      l.logger.e('Error disconnecting room in RoomBloc: $e');
      Sentry.captureException(
        e,
        stackTrace: e is Error ? e.stackTrace : null,
        withScope: (scope) {
          scope.setTag('room_action', 'leave_room');
          scope.setTag('action_type', 'disconnect');
          scope.setTag('source', 'room_bloc');
          scope.setTag('meeting_link_name', state.meetInfo.meetLinkName);
        },
      );
    }
  }

  /// Android 13+ needs POST_NOTIFICATIONS before the screen-share foreground
  /// service can post a notification. Requests once; if still denied, surfaces
  /// [RoomState.shouldShowNotificationPermissionSettings] for the inform sheet.
  Future<bool> _ensureNotificationPermissionForScreenShare(
    Emitter<RoomState> emit,
  ) async {
    if (isClosed) return false;

    final permissionService = PermissionService();
    if (await permissionService.hasNotificationPermission()) {
      return true;
    }

    final granted = await permissionService.ensureNotificationPermission();
    if (isClosed) return false;

    if (!granted) {
      if (!isClosed) {
        emit(state.copyWith(shouldShowNotificationPermissionSettings: true));
      }
      return false;
    }
    return true;
  }

  /// Starts the ongoing meeting FGS after notification permission is granted.
  /// Screen-share upgrade requires this to be active on the native side.
  Future<void> _ensureMeetingForegroundNotification() async {
    if (!android || isClosed) return;

    try {
      final notificationService = ManagerFactory().get<NotificationService>();
      await notificationService.showBackgroundNotification(
        roomName: state.meetInfo.meetName,
        callId: state.meetInfo.meetLinkName,
        requestPermissionIfMissing: false,
      );
    } catch (e) {
      l.logger.w('[RoomBloc] ensureMeetingForegroundNotification failed: $e');
    }
  }

  /// Handles toggling screen sharing.
  ///
  /// Enables or disables screen sharing for the local participant. Updates
  /// the state to reflect the current screen sharing status.
  /// On Android, checks and requests necessary permissions before enabling
  /// screen sharing to prevent the app from getting stuck.
  ///
  /// Parameters:
  /// - [event]: The toggle screen share event
  /// - [emit]: State emitter for updating the room state
  Future<void> _onToggleScreenShare(
    ToggleScreenShare event,
    Emitter<RoomState> emit,
  ) async {
    if (!isScreenShareFeatureEnabled()) {
      l.logger.w('[RoomBloc] Screen share feature flag is disabled');
      return;
    }

    if (_screenShareToggleInFlight) {
      l.logger.d('[RoomBloc] Screen share toggle ignored (in flight)');
      return;
    }

    final room = state.room;

    final participant = room.localParticipant;
    if (participant == null) return;

    _screenShareToggleInFlight = true;
    try {
      // Check actual track state to ensure state is in sync
      final actualLocalScreenShareTracks = participant.trackPublications.values
          .whereType<LocalTrackPublication>()
          .where((p) => p.isScreenShare)
          .toList();
      final actualIsLocalScreenSharing =
          actualLocalScreenShareTracks.isNotEmpty;

      // If state doesn't match actual tracks, sync it first
      if (state.isLocalScreenSharing != actualIsLocalScreenSharing) {
        l.logger.w(
          '[RoomBloc] Screen share state mismatch: state=${state.isLocalScreenSharing}, actual=$actualIsLocalScreenSharing. Syncing...',
        );
        if (!actualIsLocalScreenSharing) {
          // State says true but tracks say false - cleanup and sync state
          await _cleanupLocalScreenSharePublications(participant);
          emit(state.copyWith(isLocalScreenSharing: false));
          return;
        }
        // State says false but tracks say true - sync state
        emit(state.copyWith(isLocalScreenSharing: true));
      }

      final isLocalScreenSharing = !state.isLocalScreenSharing;

      // If disabling screen share, disable + cleanup
      if (!isLocalScreenSharing) {
        try {
          await participant.setScreenShareEnabled(false);
        } catch (e) {
          l.logger.e('Error disabling screen share: $e');
        }

        await _cleanupLocalScreenSharePublications(participant);

        if (android) {
          await _stopScreenShareForegroundService();
        }

        emit(state.copyWith(isLocalScreenSharing: false, isFullScreen: false));
        return;
      }

      // Before enabling, cleanup any lingering screen share tracks (leak guard)
      await _cleanupLocalScreenSharePublications(participant);

      // If enabling screen share, check permissions on Android first
      if (android) {
        if (!await _ensureNotificationPermissionForScreenShare(emit)) {
          return;
        }
        if (isClosed) return;

        // Permission may have been missing at join; start meeting FGS now so
        // native screen-share upgrade does not run without an active call.
        await _ensureMeetingForegroundNotification();
        if (isClosed) return;

        // Step A: ask the system for MediaProjection consent. This shows the
        // "Start now / Cancel" dialog. If the user cancels, abort silently —
        // emitting a state update would surface a stale loading indicator.
        final hasCapturePermission = await Helper.requestCapturePermission();
        if (!hasCapturePermission) {
          l.logger.i(
            '[RoomBloc] Screen share aborted: MediaProjection permission denied',
          );
          return;
        }
        if (isClosed) return;

        // Step B: Android 14+ requires a mediaProjection foreground service
        // to be running before LiveKit calls getMediaProjection().
        final fgsStarted = await _startScreenShareForegroundService();
        if (!fgsStarted) {
          l.logger.e(
            '[RoomBloc] Screen share aborted: mediaProjection FGS failed',
          );
          return;
        }
        if (isClosed) return;
      }

      // Step C: publish the screen-share track via LiveKit.
      // NOTE: captureScreenAudio is unsupported on iOS (handled by the
      // Broadcast Extension), so we only enable it elsewhere.
      final captureScreenAudio = !iOS;
      final screenShareCaptureOptions = event.screenShareSourceId != null
          ? room.roomOptions.defaultScreenShareCaptureOptions.copyWith(
              sourceId: event.screenShareSourceId,
            )
          : null;
      try {
        await participant.setScreenShareEnabled(
          true,
          captureScreenAudio: captureScreenAudio,
          screenShareCaptureOptions: screenShareCaptureOptions,
        );
        // Re-arm the E2EE key immediately after the new screen-share track
        // is published. LiveKit builds the frame cryptor per track; if a
        // key rotation was mid-flight at publish time the cryptor can pin
        // to a stale keyIndex, leaving remote (web) peers unable to
        // decrypt the screen share until the next epoch change forces a
        // re-set. See [RoomManager.refreshE2EEKey].
        await roomManager?.refreshE2EEKey(room);
        emit(state.copyWith(isLocalScreenSharing: true, isFullScreen: false));
      } catch (e) {
        l.logger.e('Error enabling screen share: $e');
        // Publish failed — roll the foreground service back so we don't
        // leak a dangling mediaProjection notification on Android.
        if (android) {
          await _stopScreenShareForegroundService();
        }
        emit(state.copyWith(isLocalScreenSharing: false));
        await _cleanupLocalScreenSharePublications(participant);
      }
    } finally {
      _screenShareToggleInFlight = false;
    }
  }

  /// Start auto fullscreen timer, which will enter fullscreen after
  /// `autoFullScreenDelay` if no user interaction is detected.
  ///
  /// While a screen share (local or remote) is active, the timer fires but
  /// skips entering fullscreen and reschedules itself; that way normal
  /// auto-fullscreen behavior resumes as soon as sharing ends without
  /// requiring an explicit "start timer" event from the UI.
  void _startAutoFullScreenTimer() {
    if (desktop) return;
    try {
      _cancelFullScreenTimer();
      _autoFullScreenTimer = Timer(autoFullScreenDelay, () {
        if (isClosed) return;
        if (state.isLocalScreenSharing) {
          // Local screen share in progress — keep the controls bar visible and
          // poll again after the same delay.
          _startAutoFullScreenTimer();
          return;
        }
        if (!state.isFullScreen) {
          add(ToggleFullScreen());
        }
      });
    } catch (e) {
      l.logger.e('[RoomBloc] Error starting auto fullscreen timer: $e');
    }
  }

  /// Handle StartAutoFullScreenTimer event
  void _onStartAutoFullScreenTimer(
    StartAutoFullScreenTimer event,
    Emitter<RoomState> emit,
  ) {
    _startAutoFullScreenTimer();
  }

  void _cancelFullScreenTimer() {
    try {
      _autoFullScreenTimer?.cancel();
    } catch (e) {
      l.logger.e('[RoomBloc] Error canceling auto fullscreen timer: $e');
    }
    _autoFullScreenTimer = null;
  }

  /// Reset auto fullscreen timer when user interacts (touch/focus)
  /// Mark isFullScreen as false to show control bar and header
  void _onResetAutoFullScreenTimer(
    ResetAutoFullScreenTimer event,
    Emitter<RoomState> emit,
  ) {
    _cancelFullScreenTimer();
    if (desktop) return;
    emit(state.copyWith(isFullScreen: false));
    _startAutoFullScreenTimer();
  }

  /// Handles toggling speaker output device.
  ///
  /// Mutes/unmutes remote audio tracks by enabling/disabling the MediaStreamTrack.
  /// This mutes the audio output without unsubscribing from tracks or switching devices.
  /// Updates the state to reflect the current speaker mute status.
  ///
  /// Parameters:
  /// - [event]: The toggle speaker event
  /// - [emit]: State emitter for updating the room state
  Future<void> _onToggleSpeaker(
    ToggleSpeaker event,
    Emitter<RoomState> emit,
  ) async {
    try {
      final room = state.room;
      final currentMuted = state.isSpeakerMuted ?? false;
      final mute = !currentMuted;

      for (final p in room.remoteParticipants.values) {
        for (final pub in p.audioTrackPublications) {
          // Only process subscribed tracks that are available
          if (pub.subscribed) {
            final track = pub.track;
            if (track is RemoteAudioTrack) {
              try {
                if (mute) {
                  // Mute speaker by disabling the audio track
                  await track.disable();
                  l.logger.d('[RoomBloc] Disabled audio track: ${track.sid}');
                } else {
                  // Unmute speaker by enabling the audio track
                  await track.enable();
                  l.logger.d('[RoomBloc] Enabled audio track: ${track.sid}');
                }
              } catch (e) {
                // Log error but continue processing other tracks
                l.logger.e(
                  '[RoomBloc] Error ${mute ? "disabling" : "enabling"} audio track ${track.sid}: $e',
                );
              }
            }
          }
        }
      }

      emit(state.copyWith(isSpeakerMuted: mute));
      l.logger.d('[RoomBloc] Speaker muted: $mute');
    } catch (e) {
      l.logger.e('[RoomBloc] Error toggling speaker: $e');
    }
  }

  /// Handles toggling speakerphone on/off (Android only for now).
  ///
  /// Updates the Hardware instance's speakerphone state and emits the new state.
  ///
  /// Parameters:
  /// - [event]: The toggle speakerphone event
  /// - [emit]: State emitter for updating the room state
  Future<void> _onToggleSpeakerPhone(
    ToggleSpeakerPhone event,
    Emitter<RoomState> emit,
  ) async {
    if (!lkPlatformIs(PlatformType.android)) {
      l.logger.w('[RoomBloc] Speakerphone toggle is only supported on Android');
      return;
    }

    try {
      final currentState = state.isSpeakerPhone;
      final newState = !currentState;

      await AudioManager.instance.setSpeakerOutputPreferred(newState);
      emit(state.copyWith(isSpeakerPhone: newState));
      await _persistSpeakerPhonePreference(newState);

      l.logger.d('Speakerphone ${newState ? "enabled" : "disabled"}');
    } catch (e) {
      l.logger.e('Error toggling speakerphone: $e');
    }
  }

  /// Handles setting speakerphone state (Android only for now).
  ///
  /// Updates the Hardware instance's speakerphone state and emits the new state.
  ///
  /// Parameters:
  /// - [event]: The set speakerphone event with enabled flag
  /// - [emit]: State emitter for updating the room state
  Future<void> _onSetSpeakerPhone(
    SetSpeakerPhone event,
    Emitter<RoomState> emit,
  ) async {
    if (!lkPlatformIs(PlatformType.android)) {
      l.logger.w(
        '[RoomBloc] Speakerphone setting is only supported on Android',
      );
      return;
    }

    try {
      await AudioManager.instance.setSpeakerOutputPreferred(event.enabled);
      emit(state.copyWith(isSpeakerPhone: event.enabled));
      await _persistSpeakerPhonePreference(event.enabled);

      l.logger.d('Speakerphone ${event.enabled ? "enabled" : "disabled"}');
    } catch (e) {
      l.logger.e('Error setting speakerphone: $e');
    }
  }

  Future<void> _onAudioOutputDevicesChanged(
    AudioOutputDevicesChanged event,
    Emitter<RoomState> emit,
  ) async {
    if (state.isRejoining) {
      return;
    }

    final nextCount = event.audioDeviceCount;
    if (nextCount != null && nextCount != state.audioDeviceCount && android) {
      AudioManager.instance
          .setSpeakerOutputPreferred(state.isSpeakerPhone)
          .catchError((e) {
            l.logger.e('[RoomBloc] Error reapplying speakerphone state: $e');
          });
    }

    emit(
      state.copyWith(
        audioDeviceCount: nextCount ?? state.audioDeviceCount,
        hasExternalAudioOutput: event.hasExternalAudioOutput,
        hasBluetoothAudioOutput: event.hasBluetoothAudioOutput,
      ),
    );
  }

  Future<void> _persistSpeakerPhonePreference(bool enabled) async {
    try {
      final prefs = ManagerFactory().get<PreferencesManager>();
      await prefs.setSpeakerPhoneEnabled(enabled: enabled);
    } catch (e) {
      l.logger.w('[RoomBloc] Error persisting speakerphone preference: $e');
    }
  }

  /// Handles setting hide self view state.
  ///
  /// Updates the state to hide or show local participant in the grid.
  /// When hideSelfView is true, the local participant's video will be removed
  /// from the participant tracks list. When false, it will be added back.
  ///
  /// Parameters:
  /// - [event]: The set hide self view event with hideSelfView flag
  /// - [emit]: State emitter for updating the room state
  void _onSetHideSelfView(SetHideSelfView event, Emitter<RoomState> emit) {
    try {
      emit(state.copyWith(hideSelfCamera: event.hideSelfView));
      l.logger.d('Hide self view: ${event.hideSelfView}');

      // Trigger a resort to update the participant tracks list
      add(DebouncedSortParticipants());
    } catch (e) {
      l.logger.e('Error setting hide self view: $e');
    }
  }

  /// Handles setting force show connection status banner state.
  ///
  /// Updates the state to force show or hide the connection status banner.
  ///
  /// Parameters:
  /// - [event]: The set force show connection status banner event with value flag
  /// - [emit]: State emitter for updating the room state
  void _onSetLiveKitReconnecting(
    SetLiveKitReconnecting event,
    Emitter<RoomState> emit,
  ) {
    try {
      emit(state.copyWith(isLiveKitReconnecting: event.isLiveKitReconnecting));
    } catch (e) {
      l.logger.e('[RoomBloc] Error setting reconnecting state: $e');
    }
  }

  void _onSetForceShowConnectionStatusBanner(
    SetForceShowConnectionStatusBanner event,
    Emitter<RoomState> emit,
  ) {
    try {
      emit(state.copyWith(forceShowConnectionStatusBanner: event.value));
      l.logger.d('Force show connection status banner: ${event.value}');
    } catch (e) {
      l.logger.e('Error setting force show connection status banner: $e');
    }
  }

  /// Handles setting audio input device in state.
  ///
  /// Updates the state with the selected audio input device ID and name.
  ///
  /// Parameters:
  /// - [event]: The set audio input device event
  /// - [emit]: State emitter for updating the room state
  Future<void> _onSetAudioInputDevice(
    SetAudioInputDevice event,
    Emitter<RoomState> emit,
  ) async {
    try {
      DenoiseAudioLifecycle.instance.abandon();
      await state.room.setAudioInputDevice(event.device);
      emit(state.copyWith(currentAudioInputDeviceId: event.device.deviceId));
      l.logger.d('Audio input device set: ${event.device.deviceId}');
      if (state.audioDenoiseEnabled && isMeetAudioDenoiseEnabled()) {
        unawaited(
          syncLocalAudioDenoiseIfNeeded(
            room: state.room,
            enabled: true,
            type: state.audioDenoiseType,
            reason: DenoiseAttachReason.deviceChange,
          ),
        );
      }
    } catch (e) {
      l.logger.e('Error setting audio input device: $e');
    }
  }

  /// Handles setting video input device in state.
  ///
  /// Updates the state with the selected video input device ID and name.
  ///
  /// Parameters:
  /// - [event]: The set video input device event
  /// - [emit]: State emitter for updating the room state
  Future<void> _onSetVideoInputDevice(
    SetVideoInputDevice event,
    Emitter<RoomState> emit,
  ) async {
    try {
      await state.room.setVideoInputDevice(event.device);
      await syncLocalCameraBackgroundEffect(
        room: state.room,
        selection: state.cameraBackgroundSelection,
      );
      emit(state.copyWith(currentVideoInputDeviceId: event.device.deviceId));
      l.logger.d('Video input device set: ${event.device.deviceId}');
    } catch (e) {
      l.logger.e('Error setting video input device: $e');
    }
  }

  /// Handles setting audio output device in state.
  ///
  /// Updates the state with the selected audio output device ID and name.
  ///
  /// Parameters:
  /// - [event]: The set audio output device event
  /// - [emit]: State emitter for updating the room state
  Future<void> _onSetAudioOutputDevice(
    SetAudioOutputDevice event,
    Emitter<RoomState> emit,
  ) async {
    try {
      await state.room.setAudioOutputDevice(event.device);
      emit(state.copyWith(currentAudioOutputDeviceId: event.device.deviceId));
      l.logger.d('Audio output device set: ${event.device.deviceId}');
    } catch (e) {
      l.logger.e('Error setting audio output device: $e');
    }
  }

  /// Handles retrying to load participants when loadFrbParticipants fails.
  ///
  /// Retries loading participants from the backend and resorts them.
  /// This is called automatically when loadFrbParticipants fails during room initialization.
  /// Will retry up to 2 times before giving up.
  ///
  /// Parameters:
  /// - [event]: The retry load participants event
  /// - [emit]: State emitter for updating the room state
  Future<void> _onRetryLoadParticipants(
    RetryLoadParticipants event,
    Emitter<RoomState> emit,
  ) async {
    try {
      l.logger.i('[RoomBloc] Retrying to load FRB participants...');
      // Use the existing retry utility function with 2 retries
      final updated = await utils.retry(
        action: loadFrbParticipants,
        maxRetries: 2,
        delay: const Duration(milliseconds: 500),
      );

      emit(state.copyWith(frbParticipantsMap: updated));
      // Resort participants after successful load
      add(SortParticipants());
      l.logger.i('[RoomBloc] Successfully loaded and sorted participants');
    } catch (e, stackTrace) {
      l.logger.e(
        '[RoomBloc] Failed to load FRB participants after retries: $e',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Handles updating the video frames per second (FPS) setting.
  ///
  /// Updates the FPS in the state and triggers participant sorting to apply
  /// the new FPS setting to all video tracks.
  ///
  /// Parameters:
  /// - [event]: The update video FPS event containing the new FPS value
  /// - [emit]: State emitter for updating the room state
  void _onUpdateVideoFPS(UpdateVideoFPS event, Emitter<RoomState> emit) {
    emit(state.copyWith(fps: event.fps));
    add(SortParticipants());
  }

  /// Handles updating the video quality setting.
  ///
  /// Updates the video quality in the state and triggers participant sorting
  /// to apply the new quality setting to all video tracks.
  ///
  /// Parameters:
  /// - [event]: The update video quality event containing the new quality value
  /// - [emit]: State emitter for updating the room state
  void _onUpdateVideoQuality(
    UpdateVideoQuality event,
    Emitter<RoomState> emit,
  ) {
    emit(state.copyWith(videoQuality: event.quality));
    add(SortParticipants());
  }

  /// Handles updates to the participant track list.
  ///
  /// Updates the state with the new list of participant tracks, which may
  /// include video feeds, screen shares, and audio tracks from all participants.
  ///
  /// Parameters:
  /// - [event]: The room participant updated event containing the new track list
  /// - [emit]: State emitter for updating the room state
  void _onRoomParticipantUpdated(
    RoomParticipantUpdated event,
    Emitter<RoomState> emit,
  ) {
    // emit(state.copyWith(participantTracks: event.tracks));
  }

  /// Callback invoked when the room state updates.
  ///
  /// Triggers a debounced re-sort of participants to ensure the UI reflects the latest
  /// participant states and track configurations without excessive sorting.
  void _onRoomDidUpdate() {
    add(DebouncedSortParticipants());
  }

  /// Handles swapping between front and back camera.
  ///
  /// Enumerates available video devices, finds the current device, and switches
  /// to the opposite camera (front <-> back). If switching fails, reverts to the
  /// previous device.
  ///
  /// Parameters:
  /// - [event]: The swap camera event
  /// - [emit]: State emitter for updating the room state
  Future<void> _onSwapCamera(SwapCamera event, Emitter<RoomState> emit) async {
    final participant = state.room.localParticipant;
    if (participant == null) {
      l.logger.w('Cannot swap camera: no local participant');
      return;
    }
    try {
      final currentCameraPosition = state.currentCameraPosition;
      if (currentCameraPosition == null) {
        l.logger.w('Cannot swap camera: no current camera position');
        return;
      }
      final newCameraPosition = currentCameraPosition.switched();
      final track = participant.videoTrackPublications.firstOrNull?.track;
      try {
        if (track != null) {
          await track.setCameraPosition(newCameraPosition);
          await syncLocalCameraBackgroundEffect(
            room: state.room,
            selection: state.cameraBackgroundSelection,
          );
        }
        emit(state.copyWith(currentCameraPosition: newCameraPosition));
      } catch (e) {
        // If the switching actually fails, reset it to the previous device
        l.logger.e('Error swapping camera: $e');
        rethrow;
      }
    } catch (e, stackTrace) {
      l.logger.e(
        'Error in swap camera handler: $e',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Handles the MLS group update event.
  ///
  /// Fetches the latest group key and display code from the app core,
  /// updates the E2EE manager with the new key, and emits updated state.
  ///
  /// Parameters:
  /// - [event]: The MLS group updated event
  /// - [emit]: State emitter for updating the room state
  Future<void> _onMlsGroupUpdated(
    MlsGroupUpdated event,
    Emitter<RoomState> emit,
  ) async {
    try {
      final appCoreManager = ManagerFactory().get<AppCoreManager>();

      // Fetch group key and display code in parallel for better performance
      final results = await Future.wait([
        appCoreManager.appCore.getGroupKey(),
        appCoreManager.appCore.getGroupDisplayCode(),
        appCoreManager.appCore.getGroupLen(),
      ]);

      final participantsCount = state.room.remoteParticipants.length + 1;

      final groupKeyResult = results[0] as (String, BigInt);
      final displayCode = results[1] as String;
      final mlsGroupLen = results[2] as int;

      final groupKey = groupKeyResult.$1;
      final epoch = groupKeyResult.$2;
      final newEpochStr = epoch.toString();
      final epochChanged = state.epoch != newEpochStr;

      if (epochChanged) {
        await state.room.safeSetKeyWithEpoch(groupKey, epoch);
        final keyIndex =
            state.room.e2eeManager?.keyProvider.getKeyIndexFromEpoch(epoch) ??
            epoch.toInt();
        await state.room.safeSetKeyIndex(keyIndex);
      }

      if (kDebugMode) {
        l.logger.d('Latest MLS group epoch: $epoch');
        l.logger.d('Latest group display code: $displayCode');
      }
      // Emit updated state with new epoch / displayCode / counts.
      emit(
        state.copyWith(
          epoch: newEpochStr,
          displayCode: displayCode,
          participantsCount: participantsCount,
          mlsGroupLen: mlsGroupLen,
        ),
      );
    } catch (e, stackTrace) {
      l.logger.e(
        'Failed to update MLS group: $e',
        error: e,
        stackTrace: stackTrace,
      );
      // Don't emit on error to avoid corrupting state
    }
  }

  /// Handles the room disposal event.
  ///
  /// Cleans up resources by removing room listeners and disposing of both
  /// the event listener and the LiveKit room instance. This ensures proper
  /// cleanup when leaving or closing a room.
  ///
  /// Parameters:
  /// - [event]: The room disposal event
  /// - [emit]: State emitter for updating the room state
  Future<void> _onRoomDisposed(
    RoomDisposed event,
    Emitter<RoomState> emit,
  ) async {
    cancelPendingCameraVideoTrackCheckTimer();

    final room = state.room;
    final listener = state.listener;

    // End call activity when room is disposed
    await CallActivityChannel.end(immediately: true);

    room.removeListener(_onRoomDidUpdate);
    await listener.dispose();
    await room.dispose();

    // emit(const RoomState());
  }
}
