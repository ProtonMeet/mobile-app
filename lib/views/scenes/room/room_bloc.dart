import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:logger/logger.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/helper/extension/bridge_error.extension.dart';
import 'package:meet/helper/extension/frb_upcoming_meeting.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/helper/extension/proton.meet.key.extension.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/channels/call_activity_channel.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/managers/room.manager.dart';
import 'package:meet/rust/proton_meet/models/meet_info.dart';
import 'package:meet/rust/proton_meet/user_subscription.dart';
import 'package:meet/views/scenes/prejoin/prejoin_arguments.dart';
import 'package:meet/views/scenes/utils.dart' as utils;
import 'package:sentry/sentry.dart';

import 'room_bloc_alone_meeting.dart';
import 'room_bloc_connection_check.dart';
import 'room_bloc_data.dart';
import 'room_bloc_debug_logging.dart';
import 'room_bloc_feature_flags.dart';
import 'room_bloc_participants.dart';
import 'room_bloc_pip.dart';
import 'room_bloc_reconnection_listeners.dart';
import 'room_bloc_rejoin.dart';
import 'room_bloc_settings.dart';
import 'room_bloc_tracks.dart';
import 'room_event.dart';
import 'room_event_bridge.dart';
import 'room_state.dart';

/// BLoC (Business Logic Component) for managing room state and interactions.
///
/// This class handles all room-related events including participant management,
/// screen sharing, video quality settings, chat messages, and encryption/decryption.
/// It integrates with LiveKit for real-time communication and manages the room's
/// encryption key for secure messaging.
class RoomBloc extends Bloc<RoomBlocEvent, RoomState>
    with
        RoomEventsBinding,
        RoomParticipantsHandlers,
        RoomTracksHandlers,
        RoomDataHandlers,
        RoomAloneMeetingHandlers,
        RoomPipHandlers,
        RoomConnectionCheckHandlers,
        RoomRejoinHandlers,
        RoomReconnectionListeners,
        RoomBlocDebugLogging,
        RoomFeatureFlagsHandlers,
        RoomSettingsHandlers {
  // Debounce timing constants for participant sorting,
  //    not sure this will work well logic could be changed later
  static const int _debounceMsLargeMeeting = 500;
  static const int _debounceMsSmallMeeting = 200;

  Timer? _sortTimer;
  DateTime? _callStartTime;

  StreamSubscription? _deviceChangeSub;

  // Debounce timer for SortParticipants to reduce excessive sorting with many participants
  Timer? _sortDebounceTimer;
  bool _sortPending = false;

  bool _screenShareToggleInFlight = false;
  static const int _joinLeaveChatSuppressThreshold = 50;
  Timer? _roomHealthSampleTimer;

  // Auto fullscreen timer for screenshare
  Timer? _autoFullScreenTimer;

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
    _sortTimer?.cancel();
    _sortDebounceTimer?.cancel();
    _roomHealthSampleTimer?.cancel();
    _cancelFullScreenTimer();
    _deviceChangeSub?.cancel();
    disposeReconnectionListeners();
    stopAloneCheckTimer();
    stopConnectionHealthCheck();

    await CallActivityChannel.end();

    await disposePip();

    // Dispose room manager
    await roomManager?.dispose();

    state.room.removeListener(_onRoomDidUpdate);
    await state.listener.cancelAll();
    await state.listener.dispose();

    await state.room.disconnect();
    await state.room.dispose();
    return super.close();
  }

  /// Debounced version of SortParticipants to reduce excessive sorting
  /// with large participant counts. Waits for events to settle before sorting.
  /// Handler for DebouncedSortParticipants event
  void _onDebouncedSortParticipants(
    DebouncedSortParticipants event,
    Emitter<RoomState> emit,
  ) {
    _sortPending = true;
    _sortDebounceTimer?.cancel();

    // With large meetings, use longer debounce to batch events
    // Use shorter debounce for smaller groups for responsiveness
    final participantCount = state.room.remoteParticipants.length + 1;
    final debounceMs = participantCount > largeMeetingThreshold
        ? _debounceMsLargeMeeting
        : _debounceMsSmallMeeting;

    _sortDebounceTimer = Timer(Duration(milliseconds: debounceMs), () {
      if (_sortPending) {
        _sortPending = false;
        add(SortParticipants());
      }
    });
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
    on<RoomDisposed>(_onRoomDisposed);
    on<DebouncedSortParticipants>(_onDebouncedSortParticipants);
    on<RetryLoadParticipants>(_onRetryLoadParticipants);

    /// register participant handlers
    /// see: room_bloc_participants.dart
    registerParticipantHandlers();

    /// register tracks handlers
    /// see: room_bloc_tracks.dart
    registerTracksHandlers();

    /// register chat handlers
    /// see: room_bloc_chat.dart
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

    on<AddSystemMessage>(_onAddSystemMessageReceived);

    /// register system message handlers
    on<ToggleFullScreen>(_onToggleFullScreen);
    on<ToggleChatBubble>(_onToggleChatBubble);
    on<ToggleParticipantList>(_onToggleParticipantList);
    on<LeaveRoom>(_onLeaveRoom);
    on<ToggleScreenShare>(_onToggleScreenShare);
    on<StartAutoFullScreenTimer>(_onStartAutoFullScreenTimer);
    on<ResetAutoFullScreenTimer>(_onResetAutoFullScreenTimer);
    on<ToggleSpeaker>(_onToggleSpeaker);
    on<ToggleSpeakerPhone>(_onToggleSpeakerPhone);
    on<SetSpeakerPhone>(_onSetSpeakerPhone);
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
    on<RoomMessageReceived>(_onRoomMessageReceived);
    on<MlsGroupUpdated>(_onMlsGroupUpdated);

    /// video operations
    on<SwapCamera>(_onSwapCamera);
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
    _roomHealthSampleTimer = Timer.periodic(const Duration(seconds: 60), (_) {
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

    final appCoreManager = ManagerFactory().get<AppCoreManager>();
    final userID = appCoreManager.userID;
    if (userID != null) {
      await appCoreManager.appCore
          .getUser(userId: userID)
          .then((value) {
            emit(state.copyWith(isPaidUser: isPaid(user: value)));
          })
          .catchError((e) {
            l.logger.e("error getting user: $e");
          });
    }

    // Start checking if user is alone
    startAloneCheckTimer();

    // Start connection health check
    startConnectionHealthCheck();

    // Periodic sampling for subscription creep / leaks
    _startRoomHealthSampling();

    // Setup MLS sync state listener
    setupMlsSyncStateListener();

    // Setup LiveKit listeners (bridge) See: room_event_bridge.dart
    setUpListeners();

    state.room.addListener(_onRoomDidUpdate);

    l.logger.d('RoomInitialized: ${event.room.name}');

    // Initialize camera enabled state
    final initialCameraEnabled =
        event.room.localParticipant?.isCameraEnabled() ?? false;

    // Initialize feature flags
    // ignore: no_leading_underscores_for_local_identifiers
    final _isMeetMobileSpeakerToggleEnabled =
        isMeetMobileSpeakerToggleEnabled();

    emit(
      state.copyWith(
        roomKey: event.roomKey,
        displayName: event.displayName,
        isCameraEnabled: initialCameraEnabled,
        isMeetMobileSpeakerToggleEnabled: _isMeetMobileSpeakerToggleEnabled,
        isSpeakerPhone: event.isSpeakerPhoneEnabled,
      ),
    );

    // Track call start time for accurate elapsed time calculation
    _callStartTime = DateTime.now();

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

    final local = await buildLocalFrbParticipant();
    emit(state.copyWith(frbParticipantsMap: local));

    try {
      final updated = await loadFrbParticipants();
      emit(state.copyWith(frbParticipantsMap: updated));
    } catch (e, stackTrace) {
      logBridgeError(
        'RoomBloc',
        'Error loading FRB participants',
        e,
        stackTrace: stackTrace,
      );
      // Retry loading participants (will retry up to 2 times)
      add(const RetryLoadParticipants());
    }

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

    _deviceChangeSub = Hardware.instance.onDeviceChange.stream.listen((value) {
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

      // If audio device count changed and we're on Android, reset speakerphone state so it will be applied to the new device (if user is using default device)
      if (currentAudioDeviceCount != state.audioDeviceCount && android) {
        Hardware.instance.setSpeakerphoneOn(state.isSpeakerPhone).catchError((
          e,
        ) {
          l.logger.e('[RoomBloc] Error reapplying speakerphone state: $e');
        });
      }

      emit(state.copyWith(audioDeviceCount: currentAudioDeviceCount));
    });

    /// re-sorting participants periodically (longer interval for large groups)
    /// so we can make last speaker move to upper tiles
    /// Use longer interval for 100+ participants to reduce CPU load
    final participantCount = state.room.remoteParticipants.length + 1;
    final sortInterval = participantCount > 50
        ? const Duration(seconds: 5)
        : const Duration(seconds: 3);

    _sortTimer = Timer.periodic(sortInterval, (_) async {
      // Force immediate sort on timer (not debounced) to ensure periodic updates
      _sortPending = false;
      _sortDebounceTimer?.cancel();
      add(SortParticipants());
      add(MlsGroupUpdated());
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

    // Mark room as initialized, no need to wait for meeting info to be fetched
    emit(state.copyWith(isRoomInitialized: true));

    if (event.preJoinType == PreJoinType.create) {
      emit(state.copyWith(showMeetingIsReady: true));
    }

    // Fetch meeting info from appCore to show maximum participant limits to user
    try {
      final meetingInfo = await appCoreManager.appCore.getMeetingInfo(
        meetingLinkName: event.meetLinkName,
      );
      emit(state.copyWith(meetingInfo: meetingInfo));
      l.logger.d('Meeting info fetched: ${meetingInfo.meetingLinkName}');
    } catch (e) {
      l.logger.e('Error fetching meeting info: $e');
    }
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

        // Android background execution is enabled during screen share; turn it off.
        if (android) {
          try {
            if (FlutterBackground.isBackgroundExecutionEnabled) {
              await FlutterBackground.disableBackgroundExecution();
            }
          } catch (e) {
            l.logger.w('[RoomBloc] disableBackgroundExecution failed: $e');
          }
        }

        await _cleanupLocalScreenSharePublications(participant);

        emit(state.copyWith(isLocalScreenSharing: false, isFullScreen: false));
        logRoomTrackStats('after_screen_share_disable', room);
        return;
      }

      // Before enabling, cleanup any lingering screen share tracks (leak guard)
      await _cleanupLocalScreenSharePublications(participant);

      // If enabling screen share, check permissions on Android first
      if (android) {
        // Android specific
        final hasCapturePermission = await Helper.requestCapturePermission();
        if (!hasCapturePermission) {
          return;
        }

        Future<void> requestBackgroundPermission({bool isRetry = false}) async {
          // Required for android screenshare.
          try {
            bool hasPermissions = await FlutterBackground.hasPermissions;
            if (!isRetry) {
              const androidConfig = FlutterBackgroundAndroidConfig(
                notificationTitle: 'Screen Sharing',
                notificationText: 'Sharing your screen',
              );
              hasPermissions = await FlutterBackground.initialize(
                androidConfig: androidConfig,
              );
            }
            if (hasPermissions &&
                !FlutterBackground.isBackgroundExecutionEnabled) {
              await FlutterBackground.enableBackgroundExecution();
            }
          } catch (e) {
            if (!isRetry) {
              return Future<void>.delayed(
                const Duration(seconds: 1),
                () => requestBackgroundPermission(isRetry: true),
              );
            }
            l.logger.d('could not publish video: $e');
          }
        }

        await requestBackgroundPermission();
      }

      // Enable screen sharing after permission checks
      // NOTE: captureScreenAudio is expensive on iOS; keep it off by default.
      final captureScreenAudio = !iOS;
      try {
        await participant.setScreenShareEnabled(
          true,
          captureScreenAudio: captureScreenAudio,
        );
        emit(state.copyWith(isLocalScreenSharing: true));
        logRoomTrackStats('after_screen_share_enable', room);
      } catch (e) {
        l.logger.e('Error enabling screen share: $e');
        // Revert state on error + cleanup
        emit(state.copyWith(isLocalScreenSharing: false));
        await _cleanupLocalScreenSharePublications(participant);
        logRoomTrackStats('after_screen_share_enable_error', room);
      }
    } finally {
      _screenShareToggleInFlight = false;
    }
  }

  /// Start auto fullscreen timer, which will enter fullscreen after autoFullScreenDelay if no user interaction is detected
  void _startAutoFullScreenTimer() {
    try {
      _cancelFullScreenTimer();
      _autoFullScreenTimer = Timer(autoFullScreenDelay, () {
        if (isClosed) return;
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

      await Hardware.instance.setSpeakerphoneOn(newState);
      emit(state.copyWith(isSpeakerPhone: newState));

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
      await Hardware.instance.setSpeakerphoneOn(event.enabled);
      emit(state.copyWith(isSpeakerPhone: event.enabled));

      l.logger.d('Speakerphone ${event.enabled ? "enabled" : "disabled"}');
    } catch (e) {
      l.logger.e('Error setting speakerphone: $e');
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
      await state.room.setAudioInputDevice(event.device);
      emit(state.copyWith(currentAudioInputDeviceId: event.device.deviceId));
      l.logger.d('Audio input device set: ${event.device.deviceId}');
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

  /// Handles receiving a chat message from another participant.
  ///
  /// Adds the received message to the message list, associating it with
  /// the sender's identity and display name.
  ///
  /// Parameters:
  /// - [event]: The room message received event containing message and sender info
  /// - [emit]: State emitter for updating the room state
  void _onRoomMessageReceived(
    RoomMessageReceived event,
    Emitter<RoomState> emit,
  ) {
    final messages = List<types.Message>.from(state.messages);
    final id = messages.length;
    final now = DateTime.now();
    final json = {
      "author": {"id": event.identity, "firstName": event.name},
      "id": id.toString(),
      "type": "text",
      "text": event.message,
      "createdAt": now.millisecondsSinceEpoch,
      "updatedAt": now.millisecondsSinceEpoch,
    };
    try {
      final typeMessage = types.Message.fromJson(json);
      messages.insert(0, typeMessage);
      emit(state.copyWith(messages: messages));
    } catch (e) {
      l.logger.e('[RoomBloc] Failed to add chat message: $e');
    }
  }

  /// Handles receiving a system message.
  ///
  /// System messages are automated notifications (e.g., "User X joined the room")
  /// that are displayed differently from regular chat messages.
  ///
  /// Parameters:
  /// - [event]: The room system message received event containing the message
  /// - [emit]: State emitter for updating the room state
  void _onAddSystemMessageReceived(
    AddSystemMessage event,
    Emitter<RoomState> emit,
  ) {
    final messages = List<types.Message>.from(state.messages);
    final id = messages.length;
    final now = DateTime.now();
    final isJoinLeaveSystemMessage =
        event.type == 'system' &&
        (event.message.startsWith('Joined ') ||
            event.message.startsWith('Left '));
    final isLargeRoom =
        state.participantTracks.length >= _joinLeaveChatSuppressThreshold ||
        state.participantsCount >= _joinLeaveChatSuppressThreshold;

    // In large rooms, suppress join/leave chat bubble spam to avoid memory/CPU growth.
    // Still log it to the stats logger below.
    if (isJoinLeaveSystemMessage && isLargeRoom) {
      logSystemLogToStatLogger(
        DateTime.now().millisecondsSinceEpoch,
        event.message,
      );
      return;
    }

    final json = {
      "author": {"id": event.identity, "firstName": event.name},
      "id": id.toString(),
      "type": event.type,
      "text": event.message,
      "createdAt": now.millisecondsSinceEpoch,
      "updatedAt": now.millisecondsSinceEpoch,
    };
    // only put messages with log level info to the chat bubble
    if (event.logLevel == Level.info) {
      try {
        final typeMessage = types.Message.fromJson(json);
        messages.insert(0, typeMessage);
        emit(state.copyWith(messages: messages));
      } catch (e) {
        e.toString();
      }
    }

    /// add system message to logger
    logSystemLogToStatLogger(
      DateTime.now().millisecondsSinceEpoch,
      event.message,
    );
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

      // Update E2EE manager with the latest group key
      await state.room.safeSetKeyWithEpoch(groupKey, epoch);
      final keyIndex =
          state.room.e2eeManager?.keyProvider.getKeyIndexFromEpoch(epoch) ??
          epoch.toInt();
      await state.room.safeSetKeyIndex(keyIndex);

      if (kDebugMode) {
        l.logger.d('Latest group key: $groupKey, epoch: $epoch');
        l.logger.d('Latest group display code: $displayCode');
      }
      // Emit updated state with new epoch and display code
      emit(
        state.copyWith(
          epoch: epoch.toString(),
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
