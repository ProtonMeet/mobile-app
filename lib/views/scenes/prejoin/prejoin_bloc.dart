import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/helper/audio_output_probe.dart';
import 'package:meet/helper/denoise/denoise_audio_capture_options.dart';
import 'package:meet/helper/extension/bridge_error.extension.dart';
import 'package:meet/helper/extension/bridge_session_check.extension.dart';
import 'package:meet/helper/extension/frb_upcoming_meeting.dart';
import 'package:meet/helper/extension/local_video_track_extension.dart';
import 'package:meet/helper/extension/media_device_list_ext.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/helper/sentry_waiting_room.dart';
import 'package:meet/helper/user.agent.dart';
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/preferences/preferences.manager.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/managers/services/denoise_audio.service.dart';
import 'package:meet/managers/services/force_upgrade.dart';
import 'package:meet/permissions/permission_service.dart';
import 'package:meet/rust/errors.dart';
import 'package:meet/rust/proton_meet/user_config.dart';
import 'package:meet/rust/proton_meet/user_subscription.dart';
import 'package:meet/views/scenes/prejoin/prejoin_event.dart';
import 'package:meet/views/scenes/prejoin/prejoin_meeting_preview.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:proton_video_effects/proton_video_effects.dart'
    show ProtonVideoEffects;

import 'prejoin_arguments.dart';
import 'prejoin_state.dart';
import 'prejoin_state_exts.dart';

class PreJoinBloc extends Bloc<PreJoinEvent, PreJoinState> {
  static const _groupInfoPollInterval = Duration(seconds: 10);

  final UserAgent userAgent;
  final ManagerFactory serviceManager;

  StreamSubscription? _deviceChangeSub;
  StreamSubscription? _audioSessionDevicesSub;
  Timer? _groupInfoPollTimer;
  Timer? _countdownTimer;
  Completer<void>? _waitingRoomAdmissionCompleter;
  Completer<void>? _leaveWaitingRoomAdmissionCompleter;

  PreJoinBloc(this.userAgent, this.serviceManager) : super(PreJoinState()) {
    on<PreJoinInitialized>(_onInitialized);
    on<PreJoinToggleAudio>(_onToggleAudio);
    on<PreJoinToggleVideo>(_onToggleVideo);
    on<RequestCameraPermission>(_onRequestCameraPermission);
    on<CameraPermissionSettingsConsumed>(
      (_, emit) =>
          emit(state.copyWith(shouldShowCameraPermissionSettings: false)),
    );
    on<MicrophonePermissionSettingsConsumed>(
      (_, emit) =>
          emit(state.copyWith(shouldShowMicrophonePermissionSettings: false)),
    );
    on<RequestMicrophonePermission>(_onRequestMicrophonePermission);
    on<ToggleE2EE>(_onToggleE2EE);
    on<SelectVideoDevice>(_onSelectVideoDevice);
    on<SelectAudioDevice>(_onSelectAudioDevice);
    on<SelectSpeakerDevice>(_onSelectSpeakerDevice);
    on<SelectVideoResolution>(_onSelectVideoResolution);
    on<WaitingRoomChanged>(
      (event, emit) => emit(state.copyWith(waitingRoomEnabled: event.enabled)),
    );

    on<VideoCodecChanged>(
      (event, emit) => emit(state.copyWith(videoCodec: event.codec)),
    );

    on<UpdateDisplayName>(_onUpdateDisplayName);
    on<SetDisplayNameFieldError>(_onSetDisplayNameFieldError);
    on<ResetLoadingState>(_onResetLoadingState);
    on<SetSpeakerPhoneEnabled>(_onSetSpeakerPhoneEnabled);
    on<PreJoinAudioOutputDevicesChanged>(
      (event, emit) => emit(
        state.copyWith(
          hasExternalAudioOutput: event.hasExternalAudioOutput,
          hasBluetoothAudioOutput: event.hasBluetoothAudioOutput,
        ),
      ),
    );
    on<SwapVideo>(_onSwapVideo);
    on<ToggleKeepDisplayName>(_onToggleKeepDisplayName);
    on<PreJoinPaidUserResolved>(
      (event, emit) => emit(state.copyWith(isPaidUser: event.isPaidUser)),
    );
    on<PreJoinAttemptJoin>(_onAttemptJoin);
    on<PreJoinHostMeetingContextResolved>(
      (event, emit) => emit(
        state.copyWith(
          isMeetingHost: true,
          role: PrejoinRole.host,
          waitingRoomEnabled: event.waitingRoomEnabled,
          roomName: event.roomName ?? state.roomName,
        ),
      ),
    );
    on<PreJoinNavigateToWaitingRoomConsumed>(
      (_, emit) => emit(state.copyWith(shouldNavigateToWaitingRoom: false)),
    );
    on<PreJoinToggleCameraBackgroundBlur>(_onToggleCameraBackgroundBlur);
    on<PreJoinStartWaitingRoomAdmission>(_onStartWaitingRoomAdmission);
    on<PreJoinPollGroupInfo>(_onPollGroupInfo);
    on<PreJoinWaitingRoomCountdownTick>(
      _onWaitingRoomCountdownTick,
      // Process ticks one at a time so concurrent handlers do not read stale seconds.
      transformer: (events, mapper) => events.asyncExpand(mapper),
    );
    on<PreJoinWaitForWaitingRoomWelcome>(_onWaitForWaitingRoomWelcome);
    on<PreJoinLeaveWaitingRoomAdmission>(_onLeaveWaitingRoomAdmission);
    on<PreJoinWaitingRoomAdmissionTimedOut>(_onWaitingRoomAdmissionTimedOut);
    on<PreJoinJoinDecisionReceived>(_onJoinDecisionReceived);
    on<PreJoinHostAcceptProceedConsumed>(
      (_, emit) =>
          emit(state.copyWith(shouldProceedToJoinAfterHostAccept: false)),
    );
    on<PreJoinJoinRequestRejectedNotificationConsumed>(
      (_, emit) => emit(
        state.copyWith(shouldShowJoinRequestRejectedNotification: false),
      ),
    );
    on<PreJoinWaitingRoomAdmissionTimedOutNotificationConsumed>(
      (_, emit) => emit(
        state.copyWith(
          shouldShowWaitingRoomAdmissionTimedOutNotification: false,
        ),
      ),
    );
  }

  @override
  Future<void> close() async {
    _cancelWaitingRoomAdmissionTimers();
    if (state.waitingRoomAdmissionPhase != WaitingRoomAdmissionPhase.inactive) {
      await _cancelWaitingRoomJoinRequestOnServer();
    }
    _finishWaitingRoomAdmission();
    // Do not await: clear may be invoked reentrantly from the join-decision
    // callback and would deadlock the FRB/Dart call stack.
    _clearJoinDecisionCallback();
    await state.audioTrack?.stop();
    await state.videoTrack?.stop();
    await _deviceChangeSub?.cancel();
    await _audioSessionDevicesSub?.cancel();
    return super.close();
  }

  /// Cancels an in-flight waiting-room admission on the server (when a join
  /// request was submitted), resets local MLS guest state, and clears UI state.
  /// No-op when the guest is not in an active waiting-room admission flow.
  Future<void> leaveWaitingRoomAdmission() async {
    if (!state.isInWaitingRoomAdmission) {
      return;
    }
    if (_leaveWaitingRoomAdmissionCompleter != null) {
      return _leaveWaitingRoomAdmissionCompleter!.future;
    }
    _leaveWaitingRoomAdmissionCompleter = Completer<void>();
    add(PreJoinLeaveWaitingRoomAdmission());
    return _leaveWaitingRoomAdmissionCompleter!.future;
  }

  Future<void> _cancelWaitingRoomJoinRequestOnServer() async {
    final meetLink = state.meetingLink;
    if (meetLink == null) {
      return;
    }

    try {
      await serviceManager
          .get<AppCoreManager>()
          .appCore
          .cancelWaitingRoomJoinRequest(meetLinkName: meetLink.meetingLinkName);
    } catch (e) {
      l.logger.w(
        '[PreJoinBloc] Failed to cancel waiting room join request: $e',
      );
    }
  }

  void _clearJoinDecisionCallback() {
    unawaited(() async {
      try {
        await serviceManager
            .get<AppCoreManager>()
            .appCore
            .clearJoinDecisionCallback();
      } catch (e) {
        l.logger.w('[PreJoinBloc] Failed to clear join decision callback: $e');
      }
    }());
  }

  Future<void> _registerJoinDecisionCallback() async {
    try {
      final appCore = serviceManager.get<AppCoreManager>().appCore;
      await appCore.setJoinDecisionCallback(
        callback: (requestId, admitted) async {
          if (!isClosed) {
            add(
              PreJoinJoinDecisionReceived(
                requestId: requestId,
                admitted: admitted,
              ),
            );
          }
        },
      );
    } catch (e) {
      l.logger.w('[PreJoinBloc] Failed to register join decision callback: $e');
    }
  }

  Future<void> _trySubmitWaitingRoomJoinRequest(
    Emitter<PreJoinState> emit,
  ) async {
    final meetLink = state.meetingLink;
    if (meetLink == null || state.waitingRoomJoinRequestId.isNotEmpty) {
      return;
    }

    emit(
      state.copyWith(
        waitingRoomAdmissionPhase: WaitingRoomAdmissionPhase.awaitingAdmission,
        waitingRoomCountdownSeconds:
            PreJoinState.waitingRoomAdmissionCountdownSeconds,
        isJoinAuthenticating: false,
      ),
    );
    _startCountdownTimer();

    try {
      final appCore = serviceManager.get<AppCoreManager>().appCore;
      final sessionKey = await appCore.getMeetingDisplayNameSessionKey();
      final response = await appCore.createJoinRequest(
        meetLinkName: meetLink.meetingLinkName,
        meetingSessionKey: sessionKey,
      );
      if (isClosed) {
        return;
      }
      if (state.waitingRoomAdmissionPhase ==
          WaitingRoomAdmissionPhase.inactive) {
        return;
      }

      emit(state.copyWith(waitingRoomJoinRequestId: response.requestId));

      add(PreJoinWaitForWaitingRoomWelcome());
    } catch (e, stackTrace) {
      if (isClosed ||
          state.waitingRoomAdmissionPhase ==
              WaitingRoomAdmissionPhase.inactive) {
        return;
      }
      _cancelWaitingRoomAdmissionTimers();
      if (e is BridgeError && e.consumeBridgeSessionIfNeeded()) {
        return;
      }
      if (isWaitingRoomJoinCancelledError(e)) {
        l.logger.i('[PreJoinBloc] Waiting room join cancelled: $e');
        return;
      }
      l.logger.e(
        '[PreJoinBloc] Failed to submit waiting room join request: $e',
        error: e,
        stackTrace: stackTrace,
      );
      captureWaitingRoomFailureToSentry(
        flow: 'guest_create_join_request',
        error: e,
        stackTrace: stackTrace,
        phase: state.waitingRoomAdmissionPhase.name,
        meetLinkName: meetLink.meetingLinkName,
      );
      emit(
        state.copyWith(
          waitingRoomAdmissionPhase: WaitingRoomAdmissionPhase.inactive,
          waitingRoomJoinRequestId: '',
          isJoinAuthenticating: false,
          error: extractErrorMessage(e),
        ),
      );
    }
  }

  Future<void> startWaitingRoomAdmission(String displayName) {
    if (_waitingRoomAdmissionCompleter != null) {
      return _waitingRoomAdmissionCompleter!.future;
    }
    _waitingRoomAdmissionCompleter = Completer<void>();
    add(PreJoinStartWaitingRoomAdmission(displayName));
    return _waitingRoomAdmissionCompleter!.future;
  }

  void _finishWaitingRoomAdmission() {
    final completer = _waitingRoomAdmissionCompleter;
    _waitingRoomAdmissionCompleter = null;
    if (completer == null || completer.isCompleted) {
      return;
    }
    completer.complete();
  }

  void _cancelWaitingRoomAdmissionTimers() {
    _groupInfoPollTimer?.cancel();
    _groupInfoPollTimer = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  bool _isGuestWaitingRoomJoin() {
    if (state.preJoinType != PreJoinType.join || state.isMeetingHost) {
      return false;
    }
    return state.hasWaitingRoom;
  }

  void _startGroupInfoPollTimer() {
    _groupInfoPollTimer?.cancel();
    _groupInfoPollTimer = Timer.periodic(_groupInfoPollInterval, (_) {
      if (!isClosed) {
        add(PreJoinPollGroupInfo());
      }
    });
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isClosed) {
        add(PreJoinWaitingRoomCountdownTick());
      }
    });
  }

  Future<void> _onStartWaitingRoomAdmission(
    PreJoinStartWaitingRoomAdmission event,
    Emitter<PreJoinState> emit,
  ) async {
    final meetLink = state.meetingLink;
    if (meetLink == null ||
        !_isGuestWaitingRoomJoin() ||
        state.isInWaitingRoomAdmission) {
      if (!state.isInWaitingRoomAdmission) {
        emit(state.copyWith(isJoinAuthenticating: false));
      }
      _finishWaitingRoomAdmission();
      return;
    }

    final displayName = event.displayName.trim();
    emit(
      state.copyWith(
        waitingRoomAdmissionDisplayName: displayName,
        waitingRoomCountdownSeconds:
            PreJoinState.waitingRoomAdmissionCountdownSeconds,
      ),
    );

    try {
      final appCore = serviceManager.get<AppCoreManager>().appCore;
      await appCore.prepareMlsSessionForWaitingRoom(
        meetLinkName: meetLink.meetingLinkName,
        meetLinkPassword: meetLink.meetingPassword,
      );
      await _registerJoinDecisionCallback();

      final hasGroupInfo = await appCore.hasMlsGroupInfo();
      if (!hasGroupInfo) {
        emit(
          state.copyWith(
            waitingRoomAdmissionPhase: WaitingRoomAdmissionPhase.hostNotStarted,
            isJoinAuthenticating: false,
          ),
        );
        _startGroupInfoPollTimer();
        _finishWaitingRoomAdmission();
        return;
      }

      await _trySubmitWaitingRoomJoinRequest(emit);
      _finishWaitingRoomAdmission();
    } catch (e, stackTrace) {
      l.logger.e(
        '[PreJoinBloc] Failed to start waiting room admission: $e',
        error: e,
        stackTrace: stackTrace,
      );
      captureWaitingRoomFailureToSentry(
        flow: 'guest_start_admission',
        error: e,
        stackTrace: stackTrace,
        phase: state.waitingRoomAdmissionPhase.name,
        meetLinkName: meetLink.meetingLinkName,
      );
      if (e is BridgeError && e.consumeBridgeSessionIfNeeded()) {
        _clearJoinDecisionCallback();
        emit(state.copyWith(isJoinAuthenticating: false));
        _finishWaitingRoomAdmission();
        return;
      }
      emit(
        state.copyWith(
          waitingRoomAdmissionPhase: WaitingRoomAdmissionPhase.inactive,
          waitingRoomJoinRequestId: '',
          isJoinAuthenticating: false,
          error: e.toString(),
        ),
      );
      _clearJoinDecisionCallback();
      _finishWaitingRoomAdmission();
    }
  }

  Future<void> _onPollGroupInfo(
    PreJoinPollGroupInfo event,
    Emitter<PreJoinState> emit,
  ) async {
    if (state.waitingRoomAdmissionPhase !=
        WaitingRoomAdmissionPhase.hostNotStarted) {
      return;
    }

    try {
      final appCore = serviceManager.get<AppCoreManager>().appCore;
      final hasGroupInfo = await appCore.hasMlsGroupInfo();
      if (!hasGroupInfo) {
        return;
      }

      _groupInfoPollTimer?.cancel();
      _groupInfoPollTimer = null;
      await _trySubmitWaitingRoomJoinRequest(emit);
    } catch (e) {
      l.logger.w('[PreJoinBloc] Group info poll failed: $e');
    }
  }

  void _onWaitingRoomCountdownTick(
    PreJoinWaitingRoomCountdownTick event,
    Emitter<PreJoinState> emit,
  ) {
    if (!state.isAwaitingWaitingRoomAdmission) {
      return;
    }

    if (state.waitingRoomCountdownSeconds <= 0) {
      return;
    }

    final next = state.waitingRoomCountdownSeconds - 1;
    if (next > 0) {
      emit(state.copyWith(waitingRoomCountdownSeconds: next));
      return;
    }

    emit(state.copyWith(waitingRoomCountdownSeconds: 0));
    add(PreJoinWaitingRoomAdmissionTimedOut());
  }

  Future<void> _onWaitingRoomAdmissionTimedOut(
    PreJoinWaitingRoomAdmissionTimedOut event,
    Emitter<PreJoinState> emit,
  ) async {
    if (!state.isAwaitingWaitingRoomAdmission) {
      return;
    }

    _cancelWaitingRoomAdmissionTimers();
    _clearJoinDecisionCallback();
    await _cancelWaitingRoomJoinRequestOnServer();
    if (isClosed) {
      return;
    }

    captureWaitingRoomTimeoutToSentry(
      flow: 'guest_admission_timeout',
      timeout: Duration(
        seconds: PreJoinState.waitingRoomAdmissionCountdownSeconds,
      ),
      meetLinkName: state.meetingLink?.meetingLinkName,
      requestId: state.waitingRoomJoinRequestId,
    );

    emit(
      state.copyWith(
        waitingRoomAdmissionPhase: WaitingRoomAdmissionPhase.inactive,
        waitingRoomJoinRequestId: '',
        waitingRoomCountdownSeconds:
            PreJoinState.waitingRoomAdmissionCountdownSeconds,
        shouldShowWaitingRoomAdmissionTimedOutNotification: true,
      ),
    );
  }

  Future<void> _onWaitForWaitingRoomWelcome(
    PreJoinWaitForWaitingRoomWelcome event,
    Emitter<PreJoinState> emit,
  ) async {
    final meetLink = state.meetingLinkForAwaitingAdmission;
    if (meetLink == null) {
      return;
    }

    try {
      final appCore = serviceManager.get<AppCoreManager>().appCore;
      await appCore.waitForWaitingRoomWelcome(
        meetLinkName: meetLink.meetingLinkName,
      );
      if (isClosed) {
        return;
      }
      if (state.waitingRoomAdmissionPhase ==
          WaitingRoomAdmissionPhase.inactive) {
        return;
      }
      _cancelWaitingRoomAdmissionTimers();
      emit(
        state.copyWith(
          waitingRoomAdmissionPhase: WaitingRoomAdmissionPhase.inactive,
          shouldProceedToJoinAfterHostAccept: true,
        ),
      );
    } catch (e, stackTrace) {
      if (isClosed ||
          state.waitingRoomAdmissionPhase ==
              WaitingRoomAdmissionPhase.inactive) {
        return;
      }
      _cancelWaitingRoomAdmissionTimers();
      if (e is BridgeError && e.consumeBridgeSessionIfNeeded()) {
        return;
      }
      if (isWaitingRoomJoinCancelledError(e)) {
        l.logger.i('[PreJoinBloc] Waiting room welcome wait cancelled: $e');
        return;
      }
      l.logger.e(
        '[PreJoinBloc] Failed waiting for waiting room welcome: $e',
        error: e,
        stackTrace: stackTrace,
      );
      captureWaitingRoomFailureToSentry(
        flow: 'guest_wait_welcome',
        error: e,
        stackTrace: stackTrace,
        phase: state.waitingRoomAdmissionPhase.name,
        meetLinkName: meetLink.meetingLinkName,
        requestId: state.waitingRoomJoinRequestId,
      );
      emit(
        state.copyWith(
          waitingRoomAdmissionPhase: WaitingRoomAdmissionPhase.inactive,
          waitingRoomJoinRequestId: '',
          error: extractErrorMessage(e),
        ),
      );
    }
  }

  Future<void> _onJoinDecisionReceived(
    PreJoinJoinDecisionReceived event,
    Emitter<PreJoinState> emit,
  ) async {
    // Server only sends join decision on reject; admit is signaled via Welcome.
    if (event.admitted || event.requestId.isEmpty) {
      return;
    }

    if (!state.isAwaitingWaitingRoomAdmission ||
        state.waitingRoomJoinRequestId.isEmpty ||
        event.requestId != state.waitingRoomJoinRequestId) {
      return;
    }

    _cancelWaitingRoomAdmissionTimers();
    _clearJoinDecisionCallback();
    try {
      await serviceManager
          .get<AppCoreManager>()
          .appCore
          .clearWaitingRoomJoinRequest();
    } catch (e) {
      l.logger.w('[PreJoinBloc] Failed to clear waiting room join request: $e');
    }

    emit(
      state.copyWith(
        waitingRoomAdmissionPhase: WaitingRoomAdmissionPhase.inactive,
        waitingRoomJoinRequestId: '',
        shouldShowJoinRequestRejectedNotification: true,
      ),
    );
  }

  Future<void> _onLeaveWaitingRoomAdmission(
    PreJoinLeaveWaitingRoomAdmission event,
    Emitter<PreJoinState> emit,
  ) async {
    try {
      _cancelWaitingRoomAdmissionTimers();
      _clearJoinDecisionCallback();
      await _cancelWaitingRoomJoinRequestOnServer();
      if (!isClosed) {
        emit(
          state.copyWith(
            waitingRoomAdmissionPhase: WaitingRoomAdmissionPhase.inactive,
            waitingRoomJoinRequestId: '',
            waitingRoomCountdownSeconds:
                PreJoinState.waitingRoomAdmissionCountdownSeconds,
          ),
        );
      }
    } finally {
      _leaveWaitingRoomAdmissionCompleter?.complete();
      _leaveWaitingRoomAdmissionCompleter = null;
    }
  }

  Future<void> _onResetLoadingState(
    ResetLoadingState event,
    Emitter<PreJoinState> emit,
  ) async {
    emit(
      state.copyWith(
        isLoggingIn: event.isLoggingIn,
        isLoggingOut: event.isLoggingOut,
      ),
    );
  }

  void _onSetDisplayNameFieldError(
    SetDisplayNameFieldError event,
    Emitter<PreJoinState> emit,
  ) {
    emit(state.copyWith(displayNameFieldError: event.message));
  }

  Future<void> _onUpdateDisplayName(
    UpdateDisplayName event,
    Emitter<PreJoinState> emit,
  ) async {
    if (state.prejoinAuthDisplayName.isNotEmpty &&
        event.displayName.trim() != state.prejoinAuthDisplayName) {
      try {
        await serviceManager
            .get<AppCoreManager>()
            .appCore
            .clearPrejoinSrpAuth();
      } catch (e) {
        l.logger.w('[PreJoinBloc] Failed to clear prejoin SRP cache: $e');
      }
      emit(state.copyWith(prejoinAuthDisplayName: ''));
    }

    emit(
      state.copyWith(
        displayName: event.displayName,
        resetDisplayNameFieldError: true,
      ),
    );

    if (state.keepDisplayNameOnDevice) {
      final sp = serviceManager.get<PreferencesManager>();
      final appCoreManager = serviceManager.get<AppCoreManager>();
      final isGuest = appCoreManager.userID == null;
      final userId = appCoreManager.userID;
      await sp.saveDisplayName(
        displayName: event.displayName,
        isGuest: isGuest,
        userId: userId,
      );
    }
  }

  Future<void> _onSetSpeakerPhoneEnabled(
    SetSpeakerPhoneEnabled event,
    Emitter<PreJoinState> emit,
  ) async {
    emit(state.copyWith(isSpeakerPhoneEnabled: event.enabled));
    try {
      final sp = serviceManager.get<PreferencesManager>();
      await sp.setSpeakerPhoneEnabled(enabled: event.enabled);
    } catch (e) {
      l.logger.w('[PreJoinBloc] Error persisting speakerphone preference: $e');
    }
  }

  Future<void> _onToggleKeepDisplayName(
    ToggleKeepDisplayName event,
    Emitter<PreJoinState> emit,
  ) async {
    emit(state.copyWith(keepDisplayNameOnDevice: event.keep));

    final sp = serviceManager.get<PreferencesManager>();
    final appCoreManager = serviceManager.get<AppCoreManager>();
    final isGuest = appCoreManager.userID == null;
    final userId = appCoreManager.userID;

    await sp.saveKeepDisplayNamePreference(
      keep: event.keep,
      isGuest: isGuest,
      userId: userId,
    );

    if (event.keep && state.displayName.isNotEmpty) {
      await sp.saveDisplayName(
        displayName: state.displayName,
        isGuest: isGuest,
        userId: userId,
      );
    } else if (!event.keep) {
      await sp.clearDisplayName(isGuest: isGuest, userId: userId);
    }
  }

  Future<void> _onInitialized(
    PreJoinInitialized event,
    Emitter<PreJoinState> emit,
  ) async {
    final appCoreManager = serviceManager.get<AppCoreManager>();
    unawaited(
      appCoreManager.warmupMeetApiConnectionIfNeeded(
        onForceUpgradeApiResponse: (e) =>
            enterForceUpgradeFromApiIfNeeded(e.field0),
      ),
    );
    unawaited(DenoiseAudioService.instance.warmUpDeepFilterIfNeeded());
    final isGuest = appCoreManager.userID == null;
    final userId = appCoreManager.userID;

    final sp = serviceManager.get<PreferencesManager>();
    final keepDisplayName = await sp.getKeepDisplayNamePreference(
      isGuest: isGuest,
      userId: userId,
    );

    final savedDisplayName = await sp.getDisplayName(
      isGuest: isGuest,
      userId: userId,
    );

    final savedSpeakerPhoneEnabled = await sp.getSpeakerPhoneEnabled();

    String initialDisplayName = event.displayName;
    bool shouldOverride = false;

    if (keepDisplayName &&
        savedDisplayName != null &&
        savedDisplayName.isNotEmpty) {
      initialDisplayName = savedDisplayName;
      shouldOverride =
          true; // We have cached name, should override auth name even if auth name is not empty
    }

    final dataProviderManager = serviceManager.get<DataProviderManager>();
    final isCameraBackgroundBlurFeatureEnabled = dataProviderManager
        .unleashDataProvider
        .isMeetCameraBackgroundBlur();
    final isWaitingRoomFeatureEnabled = dataProviderManager.unleashDataProvider
        .isMeetWaitingRoom();
    emit(
      state.copyWith(
        isLoading: true,
        displayName: initialDisplayName,
        keepDisplayNameOnDevice: keepDisplayName,
        shouldOverrideAuthDisplayName: shouldOverride,
        isVideoEnabled: event.args.isVideoEnabled,
        isAudioEnabled: event.args.isAudioEnabled,
        isPermissionGranted: false,
        meetingLink: event.args.meetingLink,
        meetingLinkUrl: event.args.meetingLinkUrl,
        preJoinType: event.args.type,
        isSpeakerPhoneEnabled: savedSpeakerPhoneEnabled,
        isCameraBackgroundBlurFeatureEnabled:
            isCameraBackgroundBlurFeatureEnabled,
        isWaitingRoomFeatureEnabled: isWaitingRoomFeatureEnabled,
      ),
    );
    if (!isGuest && userId != null) {
      unawaited(_loadPaidUserStatus(userId));
    }
    if (event.args.type == PreJoinType.join && event.args.meetingLink != null) {
      unawaited(
        _loadHostMeetingContext(event.args.meetingLink!.meetingLinkName),
      );
    }

    final permissionService = serviceManager.get<PermissionService>();
    final cameraStatus = await permissionService.cameraStatus();
    final microphoneStatus = await permissionService.microphoneStatus();
    bool isCameraPermissionGranted = false;
    bool isMicrophonePermissionGranted = false;
    // if camera permission is denied, request it
    if (cameraStatus.isGranted) {
      isCameraPermissionGranted = true;
    } else if (cameraStatus.isDenied) {
      isCameraPermissionGranted = await permissionService
          .requestCameraPermission();
    }
    // if microphone permission is denied, request it
    if (microphoneStatus.isGranted) {
      isMicrophonePermissionGranted = true;
    } else if (microphoneStatus.isDenied) {
      isMicrophonePermissionGranted = await permissionService
          .requestMicrophonePermission();
    }
    emit(
      state.copyWith(
        isCameraPermissionGranted: isCameraPermissionGranted,
        isMicrophonePermissionGranted: isMicrophonePermissionGranted,
        isVideoEnabled: isCameraPermissionGranted && state.isVideoEnabled,
        isAudioEnabled: isMicrophonePermissionGranted && state.isAudioEnabled,
      ),
    );

    // Check Mobile Speaker Toggle feature flag
    bool isMeetMobileSpeakerToggleEnabled = false;
    try {
      final dataProviderManager = serviceManager.get<DataProviderManager>();
      isMeetMobileSpeakerToggleEnabled = dataProviderManager.unleashDataProvider
          .isMeetMobileSpeakerToggle();
    } catch (e) {
      // If there's an error accessing the feature flag, default to false (hide feature)
      l.logger.w(
        '[PreJoinBloc] Error checking Mobile Speaker Toggle feature flag: $e',
      );
    }

    // Camera publish codec: MeetH264 → H264; else MeetVp9 → VP9; else VP8
    VideoCodec preferredCodec = VideoCodec.vp8;
    try {
      final dataProviderManager = serviceManager.get<DataProviderManager>();
      final unleash = dataProviderManager.unleashDataProvider;
      if (unleash.isMeetH264()) {
        preferredCodec = VideoCodec.h264;
        l.logger.i('[PreJoinBloc] H264 codec enabled by MeetH264 flag');
      } else if (unleash.isMeetVp9()) {
        preferredCodec = VideoCodec.vp9;
        l.logger.i('[PreJoinBloc] VP9 codec enabled by MeetVp9 flag');
      } else {
        l.logger.i('[PreJoinBloc] Using VP8 codec');
      }
    } catch (e) {
      l.logger.w(
        '[PreJoinBloc] Error checking video codec feature flags, defaulting to VP8: $e',
      );
    }

    // TODO(improve): this logic need to double check if we needed.
    final userConfig = await appCoreManager.appCore.getUserConfig();
    final versionDisplay = await userAgent.displayWithoutName;
    try {
      final devices = await Hardware.instance.enumerateDevices();
      final videoDevices = devices
          .where((d) => d.kind == 'videoinput')
          .toList();
      final audioDevices = devices
          .where((d) => d.kind == 'audioinput')
          .toList();
      final speakerDevices = devices
          .where((d) => d.kind == 'audiooutput')
          .toList();

      try {
        final audioSession = await AudioSession.instance;
        await _audioSessionDevicesSub?.cancel();
        _audioSessionDevicesSub = audioSession.devicesChangedEventStream.listen(
          (_) async {
            if (isClosed) {
              return;
            }
            final hardwareDevices = await Hardware.instance.enumerateDevices();
            final capabilities =
                await AudioOutputProbe.detectFromSpeakerDevices(
                  hardwareDevices.where((d) => d.kind == 'audiooutput'),
                );
            if (capabilities.hasExternal != state.hasExternalAudioOutput ||
                capabilities.hasBluetooth != state.hasBluetoothAudioOutput) {
              add(
                PreJoinAudioOutputDevicesChanged(
                  hasExternalAudioOutput: capabilities.hasExternal,
                  hasBluetoothAudioOutput: capabilities.hasBluetooth,
                ),
              );
            }
          },
        );
      } catch (e) {
        l.logger.w('[PreJoinBloc] Error checking audio session: $e');
      }

      final audioOutputCapabilities =
          await AudioOutputProbe.detectFromSpeakerDevices(speakerDevices);
      final hasExternalAudioOutput = audioOutputCapabilities.hasExternal;
      final hasBluetoothAudioOutput = audioOutputCapabilities.hasBluetooth;

      LocalAudioTrack? audioTrack;
      LocalVideoTrack? videoTrack;
      if (audioDevices.isNotEmpty &&
          state.isAudioEnabled &&
          state.isMicrophonePermissionGranted) {
        audioTrack = await LocalAudioTrack.create(
          resolveDenoiseAwareAudioCaptureOptions(
            deviceId: audioDevices.first.deviceId,
          ),
        );
        await audioTrack.start();
      }
      // Select video device: prefer front camera on mobile, otherwise use first
      MediaDevice? videoDevice;
      CameraPosition? videoPosition;
      if (mobile) {
        videoPosition = CameraPosition.front;
      } else {
        videoDevice = videoDevices.first;
      }

      if (state.isVideoEnabled && state.isCameraPermissionGranted) {
        videoTrack = await LocalVideoTrackHelper.cameraTrack(
          parameters: state.selectedVideoParameters,
          device: videoDevice,
          position: videoPosition,
          applyBackgroundBlur: state.cameraBackgroundBlurEnabled,
        );
        await videoTrack.start();
      }

      emit(
        state.copyWith(
          isLoading: false,
          videoDevices: videoDevices,
          speakerDevices: speakerDevices,
          audioDevices: audioDevices,
          selectedVideoDevice: videoDevice,
          selectedVideoPosition: videoPosition,
          selectedAudioDevice: audioDevices.isNotEmpty
              ? audioDevices.first
              : null,
          selectedSpeakerDevice: speakerDevices.isNotEmpty
              ? speakerDevices.first
              : null,
          audioTrack: audioTrack,
          videoTrack: videoTrack,
          userConfig: userConfig,
          versionDisplay: versionDisplay,
          isMeetMobileSpeakerToggleEnabled: isMeetMobileSpeakerToggleEnabled,
          hasExternalAudioOutput: hasExternalAudioOutput,
          hasBluetoothAudioOutput: hasBluetoothAudioOutput,
          videoCodec: preferredCodec, // Set based on unleash flag
        ),
      );

      await _deviceChangeSub?.cancel();
      _deviceChangeSub = Hardware.instance.onDeviceChange.stream.listen((
        value,
      ) async {
        final nextHasExternal = value
            .where((d) => d.kind == 'audiooutput')
            .hasLabelSuggestingExternalAudioOutput;
        final capabilities = await AudioOutputProbe.detect(
          labelSuggestsExternal: nextHasExternal,
        );

        add(
          PreJoinAudioOutputDevicesChanged(
            hasExternalAudioOutput: capabilities.hasExternal,
            hasBluetoothAudioOutput: capabilities.hasBluetooth,
          ),
        );
      });
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> _onToggleAudio(
    PreJoinToggleAudio event,
    Emitter<PreJoinState> emit,
  ) async {
    if (state.isAudioEnabled) {
      await state.audioTrack?.stop();
      emit(state.copyWith(isAudioEnabled: false));
    } else {
      if (!state.isMicrophonePermissionGranted) {
        final isMicrophonePermissionGranted = await PermissionService()
            .requestMicrophonePermission();
        emit(
          state.copyWith(
            isMicrophonePermissionGranted: isMicrophonePermissionGranted,
          ),
        );
        if (!isMicrophonePermissionGranted) {
          return;
        }
      }
      LocalAudioTrack? audioTrack;
      if (state.selectedAudioDevice != null) {
        audioTrack = await LocalAudioTrack.create(
          resolveDenoiseAwareAudioCaptureOptions(
            deviceId: state.selectedAudioDevice!.deviceId,
          ),
        );
        await audioTrack.start();
      }
      emit(state.copyWith(isAudioEnabled: true, audioTrack: audioTrack));
    }
  }

  Future<void> _onToggleVideo(
    PreJoinToggleVideo event,
    Emitter<PreJoinState> emit,
  ) async {
    if (state.isVideoEnabled) {
      await state.videoTrack?.stop();
      emit(state.copyWith(isVideoEnabled: false));
    } else {
      if (!state.isCameraPermissionGranted) {
        final isCameraPermissionGranted = await PermissionService()
            .requestCameraPermission();
        emit(
          state.copyWith(isCameraPermissionGranted: isCameraPermissionGranted),
        );
        if (!isCameraPermissionGranted) {
          return;
        }
      }
      final videoTrack = await LocalVideoTrackHelper.cameraTrack(
        parameters: state.selectedVideoParameters,
        device: state.selectedVideoDevice,
        position: state.selectedVideoPosition,
        applyBackgroundBlur: state.cameraBackgroundBlurEnabled,
      );
      await videoTrack.start();
      emit(state.copyWith(isVideoEnabled: true, videoTrack: videoTrack));
    }
  }

  Future<void> _onRequestCameraPermission(
    RequestCameraPermission event,
    Emitter<PreJoinState> emit,
  ) async {
    final permissionService = serviceManager.get<PermissionService>();
    final cameraStatus = await permissionService.cameraStatus();
    if (cameraStatus.isPermanentlyDenied) {
      l.logger.d('camera permission is permanently denied');
      emit(state.copyWith(shouldShowCameraPermissionSettings: true));
    } else {
      bool isCameraPermissionGranted = false;
      if (cameraStatus.isGranted) {
        isCameraPermissionGranted = true;
      }
      if (!isCameraPermissionGranted) {
        isCameraPermissionGranted = await PermissionService()
            .requestCameraPermission();
      }
      emit(
        state.copyWith(isCameraPermissionGranted: isCameraPermissionGranted),
      );
    }
  }

  Future<void> _onRequestMicrophonePermission(
    RequestMicrophonePermission event,
    Emitter<PreJoinState> emit,
  ) async {
    final permissionService = serviceManager.get<PermissionService>();
    final microphoneStatus = await permissionService.microphoneStatus();
    if (microphoneStatus.isPermanentlyDenied) {
      l.logger.d('microphone permission is permanently denied');
      emit(state.copyWith(shouldShowMicrophonePermissionSettings: true));
    } else {
      bool isMicrophonePermissionGranted = false;
      if (microphoneStatus.isGranted) {
        isMicrophonePermissionGranted = true;
      }
      if (!isMicrophonePermissionGranted) {
        isMicrophonePermissionGranted = await PermissionService()
            .requestMicrophonePermission();
      }
      emit(
        state.copyWith(
          isMicrophonePermissionGranted: isMicrophonePermissionGranted,
        ),
      );
    }
  }

  Future<void> _onSelectAudioDevice(
    SelectAudioDevice event,
    Emitter<PreJoinState> emit,
  ) async {
    await state.audioTrack?.stop();
    LocalAudioTrack? audioTrack;
    if (state.isAudioEnabled) {
      audioTrack = await LocalAudioTrack.create(
        resolveDenoiseAwareAudioCaptureOptions(deviceId: event.device.deviceId),
      );
      await audioTrack.start();
    }
    emit(
      state.copyWith(selectedAudioDevice: event.device, audioTrack: audioTrack),
    );
  }

  Future<void> _onSelectVideoDevice(
    SelectVideoDevice event,
    Emitter<PreJoinState> emit,
  ) async {
    await state.videoTrack?.stop();
    LocalVideoTrack? videoTrack;
    if (state.isVideoEnabled) {
      videoTrack = await LocalVideoTrackHelper.cameraTrack(
        parameters: state.selectedVideoParameters,
        device: event.device,
        applyBackgroundBlur: state.cameraBackgroundBlurEnabled,
      );
      await videoTrack.start();
    }
    emit(
      state.copyWith(selectedVideoDevice: event.device, videoTrack: videoTrack),
    );
  }

  Future<void> _onSelectSpeakerDevice(
    SelectSpeakerDevice event,
    Emitter<PreJoinState> emit,
  ) async {
    emit(state.copyWith(selectedSpeakerDevice: event.device));
  }

  Future<void> _onSelectVideoResolution(
    SelectVideoResolution event,
    Emitter<PreJoinState> emit,
  ) async {
    await state.videoTrack?.stop();
    LocalVideoTrack? videoTrack;
    UserConfig? userConfig;
    if (state.isVideoEnabled && state.selectedVideoDevice != null) {
      videoTrack = await LocalVideoTrackHelper.cameraTrack(
        parameters: state.selectedVideoParameters,
        device: state.selectedVideoDevice,
        applyBackgroundBlur: state.cameraBackgroundBlurEnabled,
      );
      await videoTrack.start();
      final appCoreManager = ManagerFactory().get<AppCoreManager>();
      await appCoreManager.appCore.updateCameraResolution(
        cameraResolution: event.resolution,
      );
      userConfig = await appCoreManager.appCore.getUserConfig();
    }
    emit(state.copyWith(userConfig: userConfig, videoTrack: videoTrack));
  }

  void _onToggleE2EE(ToggleE2EE event, Emitter<PreJoinState> emit) {
    emit(state.copyWith(isE2EEEnabled: !state.isE2EEEnabled));
  }

  Future<void> _onSwapVideo(SwapVideo event, Emitter<PreJoinState> emit) async {
    final newPosition = state.selectedVideoPosition?.switched();
    await state.videoTrack?.stop();
    LocalVideoTrack? videoTrack;
    if (state.isVideoEnabled) {
      videoTrack = await LocalVideoTrackHelper.cameraTrack(
        parameters: state.selectedVideoParameters,
        position: newPosition,
        applyBackgroundBlur: state.cameraBackgroundBlurEnabled,
      );
      await videoTrack.start();
    }
    emit(
      state.copyWith(
        selectedVideoPosition: newPosition,
        videoTrack: videoTrack,
      ),
    );
  }

  /// Toggles camera background blur in the prejoin preview.
  ///
  /// Enable and disable are intentionally asymmetric:
  /// - **On** — recreate the camera track with `applyBackgroundBlur: true`. Blur attaches
  ///   during track creation; it cannot be added to an already-running track.
  /// - **Off** — call [ProtonVideoEffects.detachBackgroundBlur] on the current track id only.
  ///   Avoids stop/recreate flicker; the camera keeps capturing unblurred frames.
  ///
  /// If the camera is off or the feature flag is disabled, only the preference is stored
  /// for the next track creation.
  Future<void> _onToggleCameraBackgroundBlur(
    PreJoinToggleCameraBackgroundBlur event,
    Emitter<PreJoinState> emit,
  ) async {
    if (!state.isCameraBackgroundBlurFeatureEnabled) {
      return;
    }
    final nextEnabled = !state.cameraBackgroundBlurEnabled;

    if (!state.isVideoEnabled || !state.isCameraPermissionGranted) {
      emit(state.copyWith(cameraBackgroundBlurEnabled: nextEnabled));
      return;
    }

    try {
      if (nextEnabled) {
        await state.videoTrack?.stop();
        final videoTrack = await LocalVideoTrackHelper.cameraTrack(
          parameters: state.selectedVideoParameters,
          device: state.selectedVideoDevice,
          position: state.selectedVideoPosition,
          applyBackgroundBlur: true,
        );
        await videoTrack.start();
        emit(
          state.copyWith(
            cameraBackgroundBlurEnabled: true,
            videoTrack: videoTrack,
          ),
        );
      } else {
        final trackId = state.videoTrack?.mediaStreamTrack.id;
        if (trackId != null && trackId.isNotEmpty) {
          await ProtonVideoEffects.instance.detachBackgroundBlur(
            trackId: trackId,
          );
        }
        emit(state.copyWith(cameraBackgroundBlurEnabled: false));
      }
    } catch (e) {
      l.logger.e('[PreJoinBloc] Error toggling camera background blur: $e');
    }
  }

  Future<void> _loadPaidUserStatus(String userId) async {
    try {
      final appCoreManager = serviceManager.get<AppCoreManager>();
      final userState = await appCoreManager.appCore.fetchUserState(
        userId: userId,
        forceRemote: false,
      );
      if (!isClosed) {
        add(
          PreJoinPaidUserResolved(isPaidUser: isPaid(user: userState.userData)),
        );
      }
    } catch (e) {
      l.logger.w('[PreJoinBloc] Error fetching paid user status: $e');
    }
  }

  Future<void> _loadHostMeetingContext(String meetingLinkName) async {
    if (meetingLinkName.isEmpty) {
      return;
    }

    try {
      final appCoreManager = serviceManager.get<AppCoreManager>();
      final hostContext = await resolveHostMeetingContext(
        appCoreManager: appCoreManager,
        meetingLinkName: meetingLinkName,
      );
      if (isClosed || hostContext == null) {
        return;
      }
      add(
        PreJoinHostMeetingContextResolved(
          waitingRoomEnabled: hostContext.waitingRoomEnabled,
          roomName: hostContext.roomName,
        ),
      );
    } catch (e) {
      l.logger.w('[PreJoinBloc] Failed to resolve host meeting context: $e');
    }
  }

  Future<void> _onAttemptJoin(
    PreJoinAttemptJoin event,
    Emitter<PreJoinState> emit,
  ) async {
    final meetLink = state.meetingLink;
    if (meetLink == null || state.preJoinType != PreJoinType.join) {
      return;
    }

    final displayName = event.displayName.trim();
    if (displayName.isEmpty) {
      return;
    }

    emit(
      state.copyWith(
        isJoinAuthenticating: true,
        shouldNavigateToWaitingRoom: false,
        resetDisplayNameFieldError: true,
        error: null,
        displayName: displayName,
      ),
    );

    try {
      final appCoreManager = serviceManager.get<AppCoreManager>();
      final auth = await authenticateForJoin(
        appCoreManager: appCoreManager,
        meetingLinkName: meetLink.meetingLinkName,
        meetingPassword: meetLink.meetingPassword,
        displayName: displayName,
      );

      if (isClosed) {
        return;
      }

      final serverWaitingRoomEnabled =
          auth.meetInfo.hasWaitingRoom;

      // if the feature flag is enabled, we will use the client waiting room config
      // otherwise, we will use the server waiting room config
      final clientWaitingRoomEnabled = auth.isMeetingHost
          ? (state.isWaitingRoomFeatureEnabled
                ? state.waitingRoomEnabled
                : serverWaitingRoomEnabled)
          : serverWaitingRoomEnabled;

      final pendingHostWaitingRoomSyncEnabled =
          auth.isMeetingHost &&
              serverWaitingRoomEnabled != clientWaitingRoomEnabled
          ? clientWaitingRoomEnabled
          : null;

      /// Pass the waiting room setting from the server when create the meeting or join the meeting,
      /// we will auto trigger the update waiting room flow once the host enter the meeting
      final meetingInfo = auth.isMeetingHost
          ? meetingInfoWithWaitingRoom(
              auth.meetingInfo,
              waitingRoomEnabled: serverWaitingRoomEnabled,
            )
          : auth.meetingInfo;

      final needsWaitingRoomAdmission =
          !auth.isMeetingHost && serverWaitingRoomEnabled;

      emit(
        state.copyWith(
          // Keep loading until waiting-room admission UI is shown; MLS prep runs
          // asynchronously after auth and would otherwise flash an active button.
          isJoinAuthenticating: needsWaitingRoomAdmission,
          roomName: auth.meetInfo.meetName,
          meetingInfo: meetingInfo,
          isMeetingHost: auth.isMeetingHost,
          role: auth.isMeetingHost ? PrejoinRole.host : PrejoinRole.guest,
          hasWaitingRoom: auth.isMeetingHost ? false : serverWaitingRoomEnabled,
          waitingRoomEnabled: clientWaitingRoomEnabled,
          pendingHostWaitingRoomSyncEnabled: pendingHostWaitingRoomSyncEnabled,
          prejoinAuthDisplayName: auth.authDisplayName,
        ),
      );

      if (needsWaitingRoomAdmission) {
        add(PreJoinStartWaitingRoomAdmission(displayName));
        return;
      }

      emit(state.copyWith(shouldNavigateToWaitingRoom: true));
    } on BridgeError catch (error) {
      if (error.consumeBridgeSessionIfNeeded()) {
        emit(state.copyWith(isJoinAuthenticating: false));
        return;
      }
      emit(
        state.copyWith(isJoinAuthenticating: false, error: error.userMessage),
      );
    } catch (e) {
      l.logger.e('[PreJoinBloc] Join auth failed: $e');
      emit(state.copyWith(isJoinAuthenticating: false, error: e.toString()));
    }
  }
}
