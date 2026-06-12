import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:meet/managers/services/in_app_review_service.dart';
import 'package:meet/views/components/alerts/session_expired_dialog.dart';
import 'package:meet/views/scenes/feedbacks/pre_rating_sheet.dart';
import 'package:meet/views/scenes/settings/debug/left_meeting_sheet_menu.dart';
import 'package:meet/views/scenes/settings/settings_action_item.dart';
import 'package:meet/views/scenes/settings/settings_section_header.dart';
import 'package:meet/views/scenes/signin/auth_bloc.dart';

/// Extra settings rows for debug builds only (`flutter run`, not release/profile).
final class AppSettingsDebugSection {
  AppSettingsDebugSection._();

  static List<Widget> items(BuildContext context, AuthBloc? authBloc) {
    if (!kDebugMode) {
      return const <Widget>[];
    }
    return [
      const SizedBox(height: 16),
      const SettingsSectionHeader(title: 'Debug'),
      SettingsActionItem(
        title: 'Left meeting sheet debug',
        onTap: () =>
            LeftMeetingSheetDebugMenu.show(context, authBloc: authBloc),
        isFirst: true,
      ),
      const SizedBox(height: 1),
      SettingsActionItem(
        title: 'In-app review',
        onTap: () => {InAppReviewService.tryRequestReviewForDebug()},
      ),
      const SizedBox(height: 1),
      SettingsActionItem(
        title: 'Session expired sheet debug',
        onTap: () {
          Navigator.of(context).pop();
          // To-do: check if we really need addPostFrameCallback here
          WidgetsBinding.instance.addPostFrameCallback((_) {
            unawaited(
              showSessionErrorDialog(
                context,
                onSignIn: () async {},
                onContinueWithoutSignIn: () async {},
              ),
            );
          });
        },
      ),

      const SizedBox(height: 1),
      SettingsActionItem(
        title: 'Rating sheet',
        onTap: () {
          Navigator.of(context).pop();
          PreRatingSheet.show(
            context,
            onPositiveAction: InAppReviewService.tryRequestReviewForDebug,
            onNegativeAction: () {
              InAppReviewService.onPreRatingNegativeAction();
              unawaited(authBloc?.reportProblem());
            },
          );
        },
        isLast: true,
      ),

      /// add some space between the items
      const SizedBox(height: 32),
    ];
  }
}
