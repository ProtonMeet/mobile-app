import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/manager.factory.dart';

import 'room_event.dart';
import 'room_state.dart';

/// Mixin for handling meeting settings operations in RoomBloc.
///
/// This mixin provides handlers and methods for meeting-related settings such as
/// locking/unlocking meetings.
mixin RoomSettingsHandlers on Bloc<RoomBlocEvent, RoomState> {
  /// Lock to prevent concurrent lock/unlock operations
  bool _isTogglingLockMeeting = false;

  /// Registers settings-related event handlers.
  void registerSettingsHandlers() {
    on<SetUnsubscribeVideoByDefault>(_onSetUnsubscribeVideoByDefault);
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
}
