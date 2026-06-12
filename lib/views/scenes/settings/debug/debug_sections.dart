import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:meet/managers/services/in_app_review_service.dart';
import 'package:meet/views/components/alerts/session_expired_dialog.dart';
import 'package:meet/views/scenes/feedbacks/pre_rating_sheet.dart';
import 'package:meet/views/scenes/settings/debug/background_blur_debug_screen.dart';
import 'package:meet/views/scenes/settings/debug/denoise_diagnostics_debug_sheet.dart';
import 'package:meet/views/scenes/settings/debug/left_meeting_sheet_menu.dart';
import 'package:meet/views/scenes/settings/debug/offline_file_denoise_debug_sheet.dart';
import 'package:meet/views/scenes/settings/settings_action_item.dart';
import 'package:meet/views/scenes/settings/settings_section_header.dart';
import 'package:meet/views/scenes/signin/auth_bloc.dart';
import 'package:proton_denoise/proton_denoise.dart';
import 'package:proton_video_effects/proton_video_effects.dart';

/// Developer/QA settings rows. Hidden in release via [kReleaseMode].
final class AppSettingsDebugSection {
  AppSettingsDebugSection._();

  static List<Widget> items(BuildContext context, AuthBloc? authBloc) {
    if (kReleaseMode) {
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
      if (ProtonDenoiseEffects.isSupported) ...[
        const SizedBox(height: 1),
        SettingsActionItem(
          title: 'Denoise library diagnostics',
          onTap: () => DenoiseDiagnosticsDebugSheet.show(context),
        ),
      ],
      if (ProtonVideoEffects.isSupported) ...[
        const SizedBox(height: 1),
        SettingsActionItem(
          title: 'Background blur preview',
          onTap: () => BackgroundBlurDebugScreen.show(context),
        ),
      ],
      const SizedBox(height: 1),
      SettingsActionItem(
        title: 'RNNoise file denoise (Android)',
        onTap: () => OfflineFileDenoiseDebugSheet.show(
          context,
          type: DenoiseType.rnnoise,
        ),
      ),
      const SizedBox(height: 1),
      SettingsActionItem(
        title: 'DTLN file denoise (Android)',
        onTap: () => OfflineFileDenoiseDebugSheet.show(
          context,
          type: DenoiseType.dtlnRs,
        ),
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
      const SizedBox(height: 32),
    ];
  }
}
