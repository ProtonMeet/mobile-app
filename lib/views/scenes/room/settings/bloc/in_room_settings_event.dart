import 'package:flutter/foundation.dart';
import 'package:meet/helper/background_blur/camera_background_selection.dart';
import 'package:meet/views/scenes/room/settings/bloc/in_room_settings_state.dart';

import 'package:proton_denoise/proton_denoise.dart';

abstract class InRoomSettingsEvent {}

/// Seeds host toggles from [FrbMeetInfo] when the call starts.
class InRoomSettingsInitialized extends InRoomSettingsEvent {
  InRoomSettingsInitialized({
    required this.lockMeeting,
    required this.waitingRoomEnabled,
  });

  final bool lockMeeting;
  final bool waitingRoomEnabled;
}

/// Pushed when [UnleashDataProvider] refreshes feature flags.
class InRoomSettingsFeatureFlagsChanged extends InRoomSettingsEvent {
  InRoomSettingsFeatureFlagsChanged();
}

/// Room shell and [RoomBloc] snapshot used to render non-host rows.
class InRoomSettingsBindingsUpdated extends InRoomSettingsEvent {
  InRoomSettingsBindingsUpdated({
    required this.isHost,
    required this.isPaidUser,
    required this.showLiveCaptions,
    required this.liveCaptionsAvailableForParticipants,
    required this.incomingVideoEnabled,
    required this.selfViewEnabled,
    required this.showAudioDenoise,
    required this.audioDenoiseEnabled,
    required this.audioDenoiseTypes,
    required this.selectedAudioDenoiseType,
    required this.showCameraBackground,
    required this.cameraBackgroundSelection,
    required this.showConnectionSettings,
    required this.isRejoining,
    required this.forceShowConnectionStatusBanner,
    this.onIncomingVideoChanged,
    this.onSelfViewChanged,
    this.onAudioDenoiseChanged,
    this.onAudioDenoiseTypeSelected,
    this.onBackgroundBlurChanged,
    this.onVirtualBackgroundsTap,
    this.onReconnectPressed,
    this.onForceShowConnectionStatusBannerChanged,
  });

  final bool isHost;
  final bool isPaidUser;
  final bool showLiveCaptions;
  final bool liveCaptionsAvailableForParticipants;
  final bool incomingVideoEnabled;
  final bool selfViewEnabled;
  final bool showAudioDenoise;
  final bool audioDenoiseEnabled;
  final List<DenoiseTypeUiOption> audioDenoiseTypes;
  final DenoiseType? selectedAudioDenoiseType;
  final bool showCameraBackground;
  final CameraBackgroundSelection cameraBackgroundSelection;
  final bool showConnectionSettings;
  final bool isRejoining;
  final bool forceShowConnectionStatusBanner;

  final ValueChanged<bool>? onIncomingVideoChanged;
  final ValueChanged<bool>? onSelfViewChanged;
  final ValueChanged<bool>? onAudioDenoiseChanged;
  final void Function(DenoiseType type)? onAudioDenoiseTypeSelected;
  final ValueChanged<bool>? onBackgroundBlurChanged;
  final VoidCallback? onVirtualBackgroundsTap;
  final VoidCallback? onReconnectPressed;
  final ValueChanged<bool>? onForceShowConnectionStatusBannerChanged;
}

class InRoomLockMeetingToggled extends InRoomSettingsEvent {
  InRoomLockMeetingToggled({required this.enabled});

  final bool enabled;
}

class InRoomWaitingRoomToggled extends InRoomSettingsEvent {
  InRoomWaitingRoomToggled({required this.enabled});

  final bool enabled;
}

class InRoomLiveCaptionsAvailabilityToggled extends InRoomSettingsEvent {
  InRoomLiveCaptionsAvailabilityToggled({required this.enabled});

  final bool enabled;
}

/// Optimistic update so the switch reflects immediately before bindings sync.
class InRoomIncomingVideoToggled extends InRoomSettingsEvent {
  InRoomIncomingVideoToggled({required this.enabled});

  final bool enabled;
}

/// Optimistic update so the switch reflects immediately before bindings sync.
class InRoomSelfViewToggled extends InRoomSettingsEvent {
  InRoomSelfViewToggled({required this.enabled});

  final bool enabled;
}

/// Immediate host-status update without waiting for bindings post-frame sync.
class InRoomHostStatusUpdated extends InRoomSettingsEvent {
  InRoomHostStatusUpdated({required this.isHost});

  final bool isHost;
}
