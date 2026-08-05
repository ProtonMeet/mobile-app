import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/helper/background_blur/camera_background_blur_sync.dart';
import 'package:meet/helper/denoise/denoise_audio_sync.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/helper/sentry_waiting_room.dart';
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/services/denoise_audio.service.dart';
import 'package:meet/rust/proton_meet/models/meeting_info.dart';
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

  /// Lock to prevent concurrent waiting-room setting updates
  bool _isTogglingWaitingRoom = false;

  /// Registers settings-related event handlers.
  void registerSettingsHandlers() {
    on<SetUnsubscribeVideoByDefault>(_onSetUnsubscribeVideoByDefault);
    on<MeetingInfoWaitingRoomUpdated>(_onMeetingInfoWaitingRoomUpdated);
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

  /// Toggles waiting-room policy for the meeting.
  ///
  /// Only hosts/co-hosts with admin permission can change this setting.
  Future<void> toggleWaitingRoomSetting({
    required bool value,
    required String meetLinkName,
  }) async {
    if (_isTogglingWaitingRoom) {
      l.logger.w(
        'Waiting room setting toggle already in progress, ignoring request',
      );
      return;
    }

    _isTogglingWaitingRoom = true;
    try {
      final appCoreManager = ManagerFactory().get<AppCoreManager>();
      await appCoreManager.appCore.updateWaitingRoomSetting(
        meetLinkName: meetLinkName,
        enable: value,
      );
      add(MeetingInfoWaitingRoomUpdated(enabled: value));
      l.logger.d('Waiting room ${value ? "enabled" : "disabled"}');
    } catch (e, stackTrace) {
      l.logger.e('Error toggling waiting room setting: $e');
      captureWaitingRoomFailureToSentry(
        flow: 'host_policy_toggle',
        error: e,
        stackTrace: stackTrace,
        meetLinkName: meetLinkName,
        phase: value ? 'enable' : 'disable',
      );
      rethrow;
    } finally {
      _isTogglingWaitingRoom = false;
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

  void _onMeetingInfoWaitingRoomUpdated(
    MeetingInfoWaitingRoomUpdated event,
    Emitter<RoomState> emit,
  ) {
    final info = state.meetingInfo;
    if (info == null) {
      return;
    }
    emit(
      state.copyWith(
        meetingInfo: FrbMeetingInfo(
          meetingLinkName: info.meetingLinkName,
          meetingName: info.meetingName,
          salt: info.salt,
          sessionKey: info.sessionKey,
          locked: info.locked,
          waitingRoom: event.enabled ? 1 : 0,
          manageWaitingRoom: info.manageWaitingRoom,
          personalMeeting: info.personalMeeting,
          maxDuration: info.maxDuration,
          maxParticipants: info.maxParticipants,
          expirationTime: info.expirationTime,
        ),
      ),
    );
    l.logger.d('Meeting info waiting room: ${event.enabled}');
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
    final preferred = state.audioDenoiseType;
    final type = effectiveEnabled
        ? await DenoiseAudioService.instance.resolveTypeForAttach(preferred)
        : preferred;
    if (effectiveEnabled && type == null) {
      l.logger.w(
        '[AudioDenoise] enable skipped: no type available (ff=$ffEnabled)',
      );
      return;
    }
    final effectiveType = type ?? state.audioDenoiseType;
    emit(
      state.copyWith(
        audioDenoiseEnabled: effectiveEnabled,
        audioDenoiseType: effectiveType,
      ),
    );
    if (DenoiseAudioService.isDeepFilterType(effectiveType)) {
      unawaited(
        DenoiseAudioService.instance.warmUpDeepFilterIfNeeded(
          type: effectiveType,
        ),
      );
    }
    if (type != null) {
      await syncLocalAudioDenoise(
        room: state.room,
        enabled: effectiveEnabled,
        type: type,
      );
    } else if (!effectiveEnabled) {
      await syncLocalAudioDenoise(
        room: state.room,
        enabled: false,
        type: preferred,
      );
    }
    l.logger.d(
      'Audio denoise enabled: $effectiveEnabled '
      '(requested=${event.enabled}, ff=$ffEnabled, type=${effectiveType.id})',
    );
  }

  Future<void> _onSetAudioDenoiseType(
    SetAudioDenoiseType event,
    Emitter<RoomState> emit,
  ) async {
    if (!isMeetAudioDenoiseEnabled()) {
      return;
    }
    final requested = event.type;
    if (requested == DenoiseType.none) {
      return;
    }
    final available = await DenoiseAudioService.instance
        .listAvailableTypesForUi();
    if (!available.any((info) => info.type == requested)) {
      l.logger.w('Audio denoise type ${requested.id} not available for UI');
      return;
    }
    final wasEnabled = state.audioDenoiseEnabled;
    emit(state.copyWith(audioDenoiseType: requested));
    if (DenoiseAudioService.isDeepFilterType(requested)) {
      unawaited(
        DenoiseAudioService.instance.warmUpDeepFilterIfNeeded(type: requested),
      );
    }
    if (wasEnabled) {
      // Single attach replaces the active processor atomically on native side.
      await syncLocalAudioDenoise(
        room: state.room,
        enabled: true,
        type: requested,
      );
    }
    l.logger.d('Audio denoise type: ${requested.id}');
  }
}
