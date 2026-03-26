import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/views/scenes/room/room_state_exts.dart';

import 'room_event.dart';
import 'room_state.dart';

mixin RoomAloneMeetingHandlers on Bloc<RoomBlocEvent, RoomState> {
  Timer? _aloneCheckTimer;
  int? _lastDialogShownAtMinute;

  /// Configurable duration before showing the dialog when user is alone
  /// Change this value for testing (e.g., Duration(seconds: 30) for 30 seconds)
  Duration get aloneMeetingThreshold => const Duration(minutes: 5);

  void registerAloneMeetingHandlers() {
    on<CheckAloneStatus>(_onCheckAloneStatus);
    on<StayInMeeting>(_onStayInMeeting);
  }

  void startAloneCheckTimer() {
    _aloneCheckTimer?.cancel();
    _aloneCheckTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (isClosed) {
        timer.cancel();
        return;
      }
      add(CheckAloneStatus());
    });
  }

  void stopAloneCheckTimer() {
    _aloneCheckTimer?.cancel();
    _aloneCheckTimer = null;
  }

  Future<void> _onCheckAloneStatus(
    CheckAloneStatus event,
    Emitter<RoomState> emit,
  ) async {
    final isAlone = state.isAlone;
    if (isAlone) {
      // User is alone
      DateTime? aloneSince = state.aloneSince;
      if (aloneSince == null) {
        // Just became alone, start tracking
        aloneSince = DateTime.now();
        emit(state.copyWith(aloneSince: aloneSince));
      } else {
        // Check if alone for more than the threshold duration
        final aloneDuration = DateTime.now().difference(aloneSince);
        final threshold = aloneMeetingThreshold;

        if (aloneDuration >= threshold &&
            !state.shouldShowMeetingWillEndDialog) {
          // Show dialog every threshold interval (at threshold, 2*threshold, 3*threshold, etc.)
          final totalSeconds = aloneDuration.inSeconds;
          final thresholdSeconds = threshold.inSeconds;
          final secondsSinceLastThresholdMark = totalSeconds % thresholdSeconds;

          // Show dialog at the start of each threshold interval (within first second)
          if (secondsSinceLastThresholdMark == 0 &&
              _lastDialogShownAtMinute != totalSeconds) {
            _lastDialogShownAtMinute = totalSeconds;
            emit(state.copyWith(shouldShowMeetingWillEndDialog: true));
          }
        }
      }
    } else {
      // User is not alone, reset tracking
      if (state.aloneSince != null || state.shouldShowMeetingWillEndDialog) {
        _lastDialogShownAtMinute = null;
        emit(
          state.copyWith(
            shouldShowMeetingWillEndDialog: false,
            resetAloneStatus: true,
          ),
        );
      }
    }
  }

  Future<void> _onStayInMeeting(
    StayInMeeting event,
    Emitter<RoomState> emit,
  ) async {
    // User chose to stay - reset the dialog flag so it can show again after threshold
    _lastDialogShownAtMinute = null;
    emit(
      state.copyWith(
        shouldShowMeetingWillEndDialog: false,
        resetAloneStatus: true,
      ),
    );
  }
}
