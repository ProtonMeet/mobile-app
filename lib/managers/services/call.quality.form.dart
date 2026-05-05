import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/local_toast.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/user_activity.manager.dart';
import 'package:meet/rust/errors.dart';
import 'package:sentry/sentry.dart';

/// Same threshold as web `FeedbackForm` (`RATING_THRESHOLD`).
const int kMeetingFeedbackRatingThreshold = 4;

/// Ordered labels for low-rating checkboxes (must match server-joined semantics).
List<String> meetingFeedbackAllOptionLabels(BuildContext context) => [
  context.local.call_quality_audio_breaking,
  context.local.call_quality_audio_couldnt_hear,
  context.local.call_quality_audio_others_couldnt_hear,
  context.local.call_quality_video_poor,
  context.local.call_quality_video_couldnt_see,
  context.local.call_quality_video_others_couldnt_see,
  context.local.call_quality_screen_blurry,
  context.local.call_quality_screen_couldnt_see,
  context.local.call_quality_screen_couldnt_present,
];

Future<void> submitMeetingFeedbackToApi({
  required BuildContext context,
  required String meetingLinkName,
  required int score,
  required List<String> feedbackParts,
}) async {
  final appCore = ManagerFactory().get<AppCoreManager>().appCore;
  await appCore.sendMeetingFeedback(
    meetingLinkName: meetingLinkName,
    score: score,
    feedbackParts: feedbackParts,
  );
  try {
    await ManagerFactory().get<UserActivityManager>().recordFeedbackSubmitted(
      score: score,
    );
  } catch (e, st) {
    l.logger.w('recordFeedbackSubmitted failed: $e', stackTrace: st);
    unawaited(
      Sentry.captureException(
        e,
        stackTrace: st,
        withScope: (scope) {
          scope.setTag('flow', 'meeting_feedback');
          scope.setTag('step', 'user_activity_record');
        },
      ),
    );
  }
  if (context.mounted) {
    LocalToast.showToast(
      context,
      context.local.call_quality_feedback_submitted,
    );
  }
}

void showMeetingFeedbackApiError(BuildContext context, Object e) {
  if (!context.mounted) return;
  final message = e is BridgeError_ApiResponse
      ? e.field0.error
      : context.local.call_quality_could_not_send;
  l.logger.e('sendMeetingFeedback failed: $message');
  if (kDebugMode) {
    LocalToast.showErrorToast(context, message);
  } else {
    unawaited(
      Sentry.captureException(
        e,
        stackTrace: e is Error ? e.stackTrace : null,
        withScope: (scope) {
          scope.setTag('flow', 'meeting_feedback');
          scope.setTag('step', 'send_meeting_feedback');
          if (e is BridgeError_ApiResponse) {
            scope.setContexts('api_error', {
              'code': e.field0.code,
              'error': e.field0.error,
            });
          }
        },
      ),
    );
  }
}
