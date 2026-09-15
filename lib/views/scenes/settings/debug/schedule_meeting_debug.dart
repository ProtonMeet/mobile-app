import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/scenes/core/coordinator.dart';
import 'package:meet/views/scenes/dashboard/schedule/schedule_meeting_dialog.dart';
import 'package:meet/views/scenes/room/get_participant_display_colors.dart';
import 'package:meet/views/scenes/signin/auth_bloc.dart';

/// Debug-only entry to preview [showScheduleMeetingDialog] from Settings.
final class ScheduleMeetingDebugMenu {
  ScheduleMeetingDebugMenu._();

  static void openFromSettings(BuildContext context, {AuthBloc? authBloc}) {
    if (!kDebugMode) {
      return;
    }

    final isPaidUser = authBloc?.state.isPaidUser ?? false;

    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final hostContext = Coordinator.rootNavigatorKey.currentContext;
      if (hostContext == null || !hostContext.mounted) {
        return;
      }

      unawaited(
        showScheduleMeetingDialog(
          hostContext,
          isPaidUser: isPaidUser,
          showWaitingRoom: true,
          displayColors: getParticipantDisplayColors(hostContext, 0),
          onSchedule: (data) {
            hostContext.showToast(
              'Debug schedule: ${data.title}, '
              'waitingRoom=${data.waitingRoomEnabled}',
            );
          },
        ),
      );
    });
  }
}
