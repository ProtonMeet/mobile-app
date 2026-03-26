import 'dart:async';
import 'dart:math';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/helper/extension/local_video_track_extension.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/helper/user.agent.dart';
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/preferences/preferences.manager.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/permissions/permission_service.dart';
import 'package:meet/rust/proton_meet/user_config.dart';
import 'package:meet/views/scenes/prejoin/prejoin_event.dart';
import 'package:permission_handler/permission_handler.dart';

import 'prejoin_state.dart';

class PreJoinBloc extends Bloc<PreJoinEvent, PreJoinState> {
  final UserAgent userAgent;
  final ManagerFactory serviceManager;

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
    on<ResetLoadingState>(_onResetLoadingState);
    on<SetSpeakerPhoneEnabled>(
      (event, emit) =>
          emit(state.copyWith(isSpeakerPhoneEnabled: event.enabled)),
    );
    on<SwapVideo>(_onSwapVideo);
    on<ToggleKeepDisplayName>(_onToggleKeepDisplayName);
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

  Future<void> _onUpdateDisplayName(
    UpdateDisplayName event,
    Emitter<PreJoinState> emit,
  ) async {
    emit(state.copyWith(displayName: event.displayName));

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

  String _generateAnonymousDisplayName() {
    final random = Random.secure();
    final number = random.nextInt(999) + 1; // Generate number between 1-9999
    return 'Anonymous user$number';
  }

  Future<void> _onInitialized(
    PreJoinInitialized event,
    Emitter<PreJoinState> emit,
  ) async {
    final appCoreManager = serviceManager.get<AppCoreManager>();
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

    String initialDisplayName = event.displayName;
    bool shouldOverride = false;

    if (keepDisplayName &&
        savedDisplayName != null &&
        savedDisplayName.isNotEmpty) {
      initialDisplayName = savedDisplayName;
      shouldOverride =
          true; // We have cached name, should override auth name even if auth name is not empty
    }
    if (initialDisplayName.isEmpty) {
      initialDisplayName = _generateAnonymousDisplayName();
    }

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
      ),
    );

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

      LocalAudioTrack? audioTrack;
      LocalVideoTrack? videoTrack;
      if (audioDevices.isNotEmpty &&
          state.isAudioEnabled &&
          state.isMicrophonePermissionGranted) {
        audioTrack = await LocalAudioTrack.create(
          AudioCaptureOptions(deviceId: audioDevices.first.deviceId),
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
          videoCodec: preferredCodec, // Set based on unleash flag
        ),
      );
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
          AudioCaptureOptions(deviceId: state.selectedAudioDevice!.deviceId),
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
        AudioCaptureOptions(deviceId: event.device.deviceId),
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
}
