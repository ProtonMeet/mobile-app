import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/helper/background_blur/camera_background_blur_sync.dart';
import 'package:meet/helper/denoise/denoise_audio_sync.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/services/denoise_audio.service.dart';
import 'package:proton_denoise/proton_denoise.dart';

import 'room_bloc_feature_flags.dart';
import 'room_event.dart';
import 'room_state.dart';

/// Mixin for handling meeting settings operations in RoomBloc.
///
/// This mixin provides handlers and methods for meeting-related settings such as
/// locking/unlocking meetings.
///
/// The `on` clause requires both [Bloc] and [RoomFeatureFlagsHandlers] so this mixin can
/// query the live feature-flag state (e.g. [isMeetCameraBackgroundBlurEnabled]) without
/// duplicating the try/catch wrapping. `RoomBloc` must list [RoomFeatureFlagsHandlers]
/// before [RoomSettingsHandlers] in its `with` clause to satisfy the constraint.
mixin RoomSettingsHandlers
    on Bloc<RoomBlocEvent, RoomState>, RoomFeatureFlagsHandlers {
  /// Lock to prevent concurrent lock/unlock operations
  bool _isTogglingLockMeeting = false;

  /// Registers settings-related event handlers.
  void registerSettingsHandlers() {
    on<SetUnsubscribeVideoByDefault>(_onSetUnsubscribeVideoByDefault);
    on<SetCameraBackgroundBlurEnabled>(_onSetCameraBackgroundBlurEnabled);
    on<SetAudioDenoiseEnabled>(_onSetAudioDenoiseEnabled);
    on<SetAudioDenoiseType>(_onSetAudioDenoiseType);
  }

  /// Toggles meeting lock state.
  ///
  /// Locks or unlocks the meeting to prevent/allow new participants from joining.
  /// Only hosts can lock/unlock meetings.
  ///
  /// Parameters:
  /// - [value]: true to lock, false to unlock
  /// - [meetLinkName]: The meeting link identifier
  ///
  /// Returns:
  /// - `Future<void>` that completes when the operation is done
  ///
  /// Throws:
  /// - Exception if the API call fails
  Future<void> toggleLockMeeting({
    required bool value,
    required String meetLinkName,
  }) async {
    if (_isTogglingLockMeeting) {
      l.logger.w('Meeting lock toggle already in progress, ignoring request');
      return;
    }

    _isTogglingLockMeeting = true;
    try {
      final appCoreManager = ManagerFactory().get<AppCoreManager>();
      if (value) {
        await appCoreManager.appCore.lockMeeting(meetLinkName: meetLinkName);
      } else {
        await appCoreManager.appCore.unlockMeeting(meetLinkName: meetLinkName);
      }
      l.logger.d('Meeting ${value ? "locked" : "unlocked"}');
    } catch (e) {
      l.logger.e('Error toggling meeting lock: $e');
      rethrow;
    } finally {
      _isTogglingLockMeeting = false;
    }
  }

  /// Sets the unsubscribe video by default state.
  ///
  /// When enabled, new video tracks will be automatically unsubscribed.
  /// This is useful for reducing bandwidth in large meetings.
  ///
  /// Parameters:
  /// - [event]: The event containing the unsubscribe value
  /// - [emit]: State emitter for updating the room state
  void _onSetUnsubscribeVideoByDefault(
    SetUnsubscribeVideoByDefault event,
    Emitter<RoomState> emit,
  ) {
    emit(state.copyWith(unsubscribeVideoByDefault: event.value));
    l.logger.d('Unsubscribe video by default: ${event.value}');
  }

  Future<void> _onSetCameraBackgroundBlurEnabled(
    SetCameraBackgroundBlurEnabled event,
    Emitter<RoomState> emit,
  ) async {
    // Force the stored value to false when the FF is off so the bloc state can never report
    // `true` while the feature is disabled. This keeps the toggle, the controls bar, and the
    // native processor in agreement on a single source of truth.
    final ffEnabled = isMeetCameraBackgroundBlurEnabled();
    final effectiveEnabled = event.enabled && ffEnabled;
    emit(state.copyWith(cameraBackgroundBlurEnabled: effectiveEnabled));
    await syncLocalCameraBackgroundBlur(
      room: state.room,
      enabled: effectiveEnabled,
    );
    l.logger.d(
      'Camera background blur enabled: $effectiveEnabled '
      '(requested=${event.enabled}, ff=$ffEnabled)',
    );
  }

  Future<void> _onSetAudioDenoiseEnabled(
    SetAudioDenoiseEnabled event,
    Emitter<RoomState> emit,
  ) async {
    final ffEnabled = isMeetAudioDenoiseEnabled();
    final effectiveEnabled = event.enabled && ffEnabled;
    final type =
        DenoiseType.fromId(state.audioDenoiseTypeId) ?? DenoiseType.rnnoise;
    emit(state.copyWith(audioDenoiseEnabled: effectiveEnabled));
    await syncLocalAudioDenoise(
      room: state.room,
      enabled: effectiveEnabled,
      type: type,
    );
    l.logger.d(
      'Audio denoise enabled: $effectiveEnabled '
      '(requested=${event.enabled}, ff=$ffEnabled, type=${type.id})',
    );
  }

  Future<void> _onSetAudioDenoiseType(
    SetAudioDenoiseType event,
    Emitter<RoomState> emit,
  ) async {
    if (!isMeetAudioDenoiseEnabled()) {
      return;
    }
    final type = DenoiseType.fromId(event.typeId);
    if (type == null || type == DenoiseType.none) {
      return;
    }
    final available = await DenoiseAudioService.instance
        .listAvailableTypesForUi();
    if (!available.any((info) => info.type == type)) {
      l.logger.w('Audio denoise type ${event.typeId} not available for UI');
      return;
    }
    final wasEnabled = state.audioDenoiseEnabled;
    emit(state.copyWith(audioDenoiseTypeId: type.id));
    if (wasEnabled) {
      await syncLocalAudioDenoise(room: state.room, enabled: true, type: type);
    }
    l.logger.d('Audio denoise type: ${type.id}');
  }
}
