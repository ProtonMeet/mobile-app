import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:meet/helper/background_blur/camera_background_selection.dart';
import 'package:meet/views/scenes/room/settings/bloc/in_room_settings_event.dart';
import 'package:proton_denoise/proton_denoise.dart';

/// Server-backed host toggles that show a spinner while the request is in flight.
enum InRoomPendingToggle { lockMeeting, waitingRoom }

/// One selectable denoise backend, shown when several are enabled via Unleash.
class DenoiseTypeUiOption extends Equatable {
  const DenoiseTypeUiOption({required this.type});

  final DenoiseType type;

  String get id => type.id;
  String get label => type.displayName;

  @override
  List<Object?> get props => [type];
}

/// Immutable snapshot for the in-call settings panel.
class InRoomSettingsState extends Equatable {
  const InRoomSettingsState({
    this.isHost = false,
    this.isPaidUser = false,
    this.showPreviewSettings = false,
    this.showWaitingRoom = false,
    this.showRecordingRows = false,
    this.lockMeeting = false,
    this.waitingRoomEnabled = false,
    this.pendingToggles = const {},
    this.incomingVideoEnabled = true,
    this.selfViewEnabled = true,
    this.showAudioDenoise = false,
    this.audioDenoiseEnabled = false,
    this.audioDenoiseTypes = const [],
    this.selectedAudioDenoiseType,
    this.showCameraBackground = false,
    this.cameraBackgroundSelection = const CameraBackgroundSelection.none(),
    this.showConnectionSettings = false,
    this.isRejoining = false,
    this.forceShowConnectionStatusBanner = false,
    this.bindingsRevision = 0,
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
  final bool showPreviewSettings;
  final bool showWaitingRoom;
  final bool showRecordingRows;

  final bool lockMeeting;
  final bool waitingRoomEnabled;
  final Set<InRoomPendingToggle> pendingToggles;

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
  final int bindingsRevision;

  final ValueChanged<bool>? onIncomingVideoChanged;
  final ValueChanged<bool>? onSelfViewChanged;
  final ValueChanged<bool>? onAudioDenoiseChanged;
  final void Function(DenoiseType type)? onAudioDenoiseTypeSelected;
  final ValueChanged<bool>? onBackgroundBlurChanged;
  final VoidCallback? onVirtualBackgroundsTap;
  final VoidCallback? onReconnectPressed;
  final ValueChanged<bool>? onForceShowConnectionStatusBannerChanged;

  bool isPending(InRoomPendingToggle toggle) => pendingToggles.contains(toggle);

  bool get backgroundBlurEnabled =>
      cameraBackgroundSelection.kind == CameraBackgroundEffectKind.blur;

  bool get showAudioDenoiseTypes =>
      showAudioDenoise &&
      audioDenoiseEnabled &&
      audioDenoiseTypes.length > 1 &&
      onAudioDenoiseTypeSelected != null;

  bool get canEditHostToggles => isHost;

  bool get canEditWaitingRoom => isHost && isPaidUser;

  InRoomSettingsState copyWith({
    bool? isHost,
    bool? isPaidUser,
    bool? showPreviewSettings,
    bool? showWaitingRoom,
    bool? showRecordingRows,
    bool? lockMeeting,
    bool? waitingRoomEnabled,
    Set<InRoomPendingToggle>? pendingToggles,
    bool? incomingVideoEnabled,
    bool? selfViewEnabled,
    bool? showAudioDenoise,
    bool? audioDenoiseEnabled,
    List<DenoiseTypeUiOption>? audioDenoiseTypes,
    DenoiseType? selectedAudioDenoiseType,
    bool? showCameraBackground,
    CameraBackgroundSelection? cameraBackgroundSelection,
    bool? showConnectionSettings,
    bool? isRejoining,
    bool? forceShowConnectionStatusBanner,
    int? bindingsRevision,
    ValueChanged<bool>? onIncomingVideoChanged,
    ValueChanged<bool>? onSelfViewChanged,
    ValueChanged<bool>? onAudioDenoiseChanged,
    void Function(DenoiseType type)? onAudioDenoiseTypeSelected,
    ValueChanged<bool>? onBackgroundBlurChanged,
    VoidCallback? onVirtualBackgroundsTap,
    VoidCallback? onReconnectPressed,
    ValueChanged<bool>? onForceShowConnectionStatusBannerChanged,
  }) {
    return InRoomSettingsState(
      isHost: isHost ?? this.isHost,
      isPaidUser: isPaidUser ?? this.isPaidUser,
      showPreviewSettings: showPreviewSettings ?? this.showPreviewSettings,
      showWaitingRoom: showWaitingRoom ?? this.showWaitingRoom,
      showRecordingRows: showRecordingRows ?? this.showRecordingRows,
      lockMeeting: lockMeeting ?? this.lockMeeting,
      waitingRoomEnabled: waitingRoomEnabled ?? this.waitingRoomEnabled,
      pendingToggles: pendingToggles ?? this.pendingToggles,
      incomingVideoEnabled:
          incomingVideoEnabled ?? this.incomingVideoEnabled,
      selfViewEnabled: selfViewEnabled ?? this.selfViewEnabled,
      showAudioDenoise: showAudioDenoise ?? this.showAudioDenoise,
      audioDenoiseEnabled: audioDenoiseEnabled ?? this.audioDenoiseEnabled,
      audioDenoiseTypes: audioDenoiseTypes ?? this.audioDenoiseTypes,
      selectedAudioDenoiseType:
          selectedAudioDenoiseType ?? this.selectedAudioDenoiseType,
      showCameraBackground:
          showCameraBackground ?? this.showCameraBackground,
      cameraBackgroundSelection:
          cameraBackgroundSelection ?? this.cameraBackgroundSelection,
      showConnectionSettings:
          showConnectionSettings ?? this.showConnectionSettings,
      isRejoining: isRejoining ?? this.isRejoining,
      forceShowConnectionStatusBanner: forceShowConnectionStatusBanner ??
          this.forceShowConnectionStatusBanner,
      bindingsRevision: bindingsRevision ?? this.bindingsRevision,
      onIncomingVideoChanged:
          onIncomingVideoChanged ?? this.onIncomingVideoChanged,
      onSelfViewChanged: onSelfViewChanged ?? this.onSelfViewChanged,
      onAudioDenoiseChanged:
          onAudioDenoiseChanged ?? this.onAudioDenoiseChanged,
      onAudioDenoiseTypeSelected:
          onAudioDenoiseTypeSelected ?? this.onAudioDenoiseTypeSelected,
      onBackgroundBlurChanged:
          onBackgroundBlurChanged ?? this.onBackgroundBlurChanged,
      onVirtualBackgroundsTap:
          onVirtualBackgroundsTap ?? this.onVirtualBackgroundsTap,
      onReconnectPressed: onReconnectPressed ?? this.onReconnectPressed,
      onForceShowConnectionStatusBannerChanged:
          onForceShowConnectionStatusBannerChanged ??
          this.onForceShowConnectionStatusBannerChanged,
    );
  }

  /// Applies a full bindings snapshot from the room shell.
  ///
  /// Unlike [copyWith], nullable callback fields are taken unconditionally so
  /// callers can clear them by passing `null`.
  InRoomSettingsState withBindings(
    InRoomSettingsBindingsUpdated event, {
    required bool showRecordingRows,
  }) {
    return InRoomSettingsState(
      isHost: event.isHost,
      isPaidUser: event.isPaidUser,
      showPreviewSettings: showPreviewSettings,
      showWaitingRoom: showWaitingRoom,
      showRecordingRows: showRecordingRows,
      lockMeeting: lockMeeting,
      waitingRoomEnabled: waitingRoomEnabled,
      pendingToggles: pendingToggles,
      incomingVideoEnabled: event.incomingVideoEnabled,
      selfViewEnabled: event.selfViewEnabled,
      showAudioDenoise: event.showAudioDenoise,
      audioDenoiseEnabled: event.audioDenoiseEnabled,
      audioDenoiseTypes: event.audioDenoiseTypes,
      selectedAudioDenoiseType: event.selectedAudioDenoiseType,
      showCameraBackground: event.showCameraBackground,
      cameraBackgroundSelection: event.cameraBackgroundSelection,
      showConnectionSettings: event.showConnectionSettings,
      isRejoining: event.isRejoining,
      forceShowConnectionStatusBanner: event.forceShowConnectionStatusBanner,
      bindingsRevision: bindingsRevision + 1,
      onIncomingVideoChanged: event.onIncomingVideoChanged,
      onSelfViewChanged: event.onSelfViewChanged,
      onAudioDenoiseChanged: event.onAudioDenoiseChanged,
      onAudioDenoiseTypeSelected: event.onAudioDenoiseTypeSelected,
      onBackgroundBlurChanged: event.onBackgroundBlurChanged,
      onVirtualBackgroundsTap: event.onVirtualBackgroundsTap,
      onReconnectPressed: event.onReconnectPressed,
      onForceShowConnectionStatusBannerChanged:
          event.onForceShowConnectionStatusBannerChanged,
    );
  }

  @override
  List<Object?> get props => [
    isHost,
    isPaidUser,
    showPreviewSettings,
    showWaitingRoom,
    showRecordingRows,
    lockMeeting,
    waitingRoomEnabled,
    pendingToggles,
    incomingVideoEnabled,
    selfViewEnabled,
    showAudioDenoise,
    audioDenoiseEnabled,
    audioDenoiseTypes,
    selectedAudioDenoiseType,
    showCameraBackground,
    cameraBackgroundSelection,
    showConnectionSettings,
    isRejoining,
    forceShowConnectionStatusBanner,
    bindingsRevision,
  ];
}
