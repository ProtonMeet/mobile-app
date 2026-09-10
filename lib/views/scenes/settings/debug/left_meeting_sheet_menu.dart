import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/managers/providers/unleash.data.provider.dart';
import 'package:meet/managers/services/in_app_review_service.dart';
import 'package:meet/rust/proton_meet/models/upcoming_meeting.dart';
import 'package:meet/views/components/settings/settings_action_item.dart';
import 'package:meet/views/components/settings/settings_section.dart';
import 'package:meet/views/scenes/core/coordinator.dart';
import 'package:meet/views/scenes/feedbacks/left_meeting_feedback_sheet.dart';
import 'package:meet/views/scenes/feedbacks/pre_rating_sheet.dart';
import 'package:meet/views/scenes/signin/auth_bloc.dart';

/// Debug-only menu to preview [showLeftMeetingBottomSheet] variants (grouped).
///
/// Only used from [kDebugMode] settings; labels are English for developers/QA.
final class LeftMeetingSheetDebugMenu {
  LeftMeetingSheetDebugMenu._();

  static void show(BuildContext context, {AuthBloc? authBloc}) {
    if (!kDebugMode) return;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (sheetContext) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: sheetContext.colors.backgroundSecondary,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Left meeting sheet (preview)',
                            style: TextStyle(
                              color: sheetContext.colors.textNorm,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.close,
                            color: sheetContext.colors.textNorm,
                          ),
                          onPressed: () =>
                              Navigator.of(sheetContext).maybePop(),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        const SettingsSectionHeader(title: 'Host'),
                        _row(
                          sheetContext,
                          title: 'Host — not logged in',
                          isFirst: true,
                          isLast: false,
                          preview: () => _preview(
                            sheetContext,
                            isHost: true,
                            isPaidUser: false,
                            authBloc: authBloc,
                          ),
                        ),
                        _row(
                          sheetContext,
                          title: 'Host — logged in, free plan',
                          isFirst: false,
                          isLast: false,
                          preview: () => _preview(
                            sheetContext,
                            isHost: true,
                            isPaidUser: false,
                            authBloc: authBloc,
                          ),
                        ),
                        _row(
                          sheetContext,
                          title: 'Host — logged in, paid plan',
                          isFirst: false,
                          isLast: false,
                          preview: () => _preview(
                            sheetContext,
                            isHost: true,
                            isPaidUser: true,
                            authBloc: authBloc,
                          ),
                        ),
                        _row(
                          sheetContext,
                          title: 'Host — alone in room',
                          isFirst: false,
                          isLast: true,
                          preview: () => _preview(
                            sheetContext,
                            isHost: true,
                            isPaidUser: false,
                            authBloc: authBloc,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const SettingsSectionHeader(title: 'Participant'),
                        _row(
                          sheetContext,
                          title: 'Participant — not logged in',
                          isFirst: true,
                          isLast: false,
                          preview: () => _preview(
                            sheetContext,
                            isHost: false,
                            isPaidUser: false,
                            authBloc: authBloc,
                          ),
                        ),
                        _row(
                          sheetContext,
                          title: 'Participant — logged in, free plan',
                          isFirst: false,
                          isLast: false,
                          preview: () => _preview(
                            sheetContext,
                            isHost: false,
                            isPaidUser: false,
                            authBloc: authBloc,
                          ),
                        ),
                        _row(
                          sheetContext,
                          title: 'Participant — logged in, paid plan',
                          isFirst: false,
                          isLast: true,
                          preview: () => _preview(
                            sheetContext,
                            isHost: false,
                            isPaidUser: true,
                            authBloc: authBloc,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const SettingsSectionHeader(title: 'Removal'),
                        _row(
                          sheetContext,
                          title: 'Participant — removed by host',
                          isFirst: true,
                          isLast: true,
                          preview: () => _preview(
                            sheetContext,
                            isHost: false,
                            isPaidUser: false,
                            isKickedOut: true,
                            authBloc: authBloc,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static Widget _row(
    BuildContext context, {
    required String title,
    required bool isFirst,
    required bool isLast,
    required Future<void> Function() preview,
  }) {
    return SettingsActionItem(
      title: title,
      isFirst: isFirst,
      isLast: isLast,
      onTap: () async {
        await preview();
      },
    );
  }

  static Future<void> _preview(
    BuildContext menuContext, {
    required AuthBloc? authBloc,
    required bool isHost,
    required bool isPaidUser,
    bool isKickedOut = false,
    bool showRejoin = true,
    String? title,
    String? content,
  }) async {
    final rootContext =
        Coordinator.rootNavigatorKey.currentState?.overlay?.context ??
        Coordinator.rootNavigatorKey.currentContext;
    if (rootContext == null) return;

    var meetFeedbackOnSkip = false;
    try {
      meetFeedbackOnSkip = ManagerFactory()
          .get<DataProviderManager>()
          .unleashDataProvider
          .isMeetFeedbackOnSkip();
    } catch (_) {}

    final meetingLink = FrbUpcomingMeeting.newForJoin(
      meetingLinkName: 'debug-left-meeting-preview',
      meetingPassword: '',
    );

    if (menuContext.mounted) {
      Navigator.of(menuContext).pop();
    }
    await Future<void>.delayed(Duration.zero);
    if (!rootContext.mounted) return;

    await showLeftMeetingBottomSheet(
      rootContext,
      meetingLink: meetingLink,
      isHost: isHost,
      isPaidUser: isPaidUser,
      isMeetMobileShowStartMeetingButtonEnabled: true,
      isKickedOut: isKickedOut,
      showRejoin: showRejoin,
      title: title,
      content: content,
      meetingLinkName: meetingLink.meetingLinkName,
      meetFeedbackOnSkipEnabled: meetFeedbackOnSkip,
      onRejoinMeeting: () {
        if (rootContext.mounted) {
          rootContext.showToast('Debug: rejoin tapped');
        }
      },
      onStartMeetingNow: () {
        if (rootContext.mounted) {
          rootContext.showToast('Debug: start meeting tapped');
        }
      },
    );

    try {
      final canShowStoreReview = await InAppReviewService.canShowStoreReview();
      if (canShowStoreReview && rootContext.mounted) {
        await PreRatingSheet.show(
          rootContext,
          onPositiveAction: InAppReviewService.tryRequestReviewForDebug,
          onNegativeAction: () => {
            InAppReviewService.onPreRatingNegativeAction(),
            unawaited(authBloc?.reportProblem()),
          },
        );
      }
    } catch (e, st) {
      l.logger.w('[Room] store review (leave): $e', stackTrace: st);
    }
  }
}
