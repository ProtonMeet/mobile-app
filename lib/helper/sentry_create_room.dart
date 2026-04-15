import 'dart:async';

import 'package:meet/helper/extension/bridge_error.extension.dart';
import 'package:meet/rust/errors.dart';
import 'package:meet/rust/proton_meet/models/meeting_type.dart';
import 'package:sentry/sentry.dart';

/// Fixed [Sentry] tag value for grouping all create-meeting failures.
const String kSentryErrorTypeCreateMeetingFailed = 'create_meeting_failed';

/// Fixed [Sentry] tag value for client-side create-meeting timeouts.
const String kSentryErrorTypeCreateMeetingTimeout = 'create_meeting_timeout';

/// Schedules Sentry work on the event loop; never throws; failures are ignored.
void _enqueueSentryReport(Future<void> Function() run) {
  unawaited(
    Future<void>.microtask(() async {
      try {
        await run();
      } catch (_) {
        // Sentry must not affect normal app logic.
      }
    }),
  );
}

/// Report create-meeting / create-room failures to Sentry (non-blocking).
void captureCreateRoomFailureToSentry({
  required String flow,
  required Object error,
  StackTrace? stackTrace,
  MeetingType? meetingType,
  bool? hasSession,
  int? meetingNameLength,
  bool? scheduledMeeting,
}) {
  final st = stackTrace ?? (error is Error ? error.stackTrace : null);
  _enqueueSentryReport(
    () => Sentry.captureException(
      error,
      stackTrace: st,
      withScope: (scope) {
        scope.setTag('error_type', kSentryErrorTypeCreateMeetingFailed);
        scope.setTag('create_room_flow', flow);
        if (meetingType != null) {
          scope.setTag('meeting_type', meetingType.name);
        }
        if (hasSession != null) {
          scope.setTag('has_session', hasSession.toString());
        }
        if (scheduledMeeting != null) {
          scope.setTag('scheduled_meeting', scheduledMeeting.toString());
        }

        scope.setContexts('create_meeting_details', {
          'flow': flow,
          'error_runtime_type': error.runtimeType.toString(),
          'error_message': error.toString(),
          if (meetingNameLength != null)
            'meeting_name_length': meetingNameLength.toString(),
          if (scheduledMeeting != null)
            'scheduled_meeting': scheduledMeeting.toString(),
          if (hasSession != null) 'has_session': hasSession.toString(),
        });

        if (error is BridgeError_ApiResponse) {
          scope.setContexts('api_error', {
            'code': error.field0.code,
            'error': error.field0.error,
            'details': error.field0.details,
          });
        } else if (error is BridgeError_MeetCore) {
          final raw = error.field0;
          scope.setContexts('meet_core_error', {
            'message': meetCoreServiceMessageLine(raw),
            'details':
                parseMeetCoreServiceErrorDetails(raw) ?? '(no parsed details)',
            'raw': raw,
          });
        } else if (error is BridgeError_MeetCoreAny) {
          scope.setContexts('meet_core_any_error', {'message': error.field0});
        }
      },
    ),
  );
}

/// Create-meeting did not complete within the client timeout (non-blocking).
void captureCreateRoomTimeoutToSentry({
  required String flow,
  required Duration timeout,
  MeetingType? meetingType,
  bool? hasSession,
  int? meetingNameLength,
}) {
  _enqueueSentryReport(
    () => Sentry.captureMessage(
      'Create room timed out after ${timeout.inSeconds}s (flow: $flow)',
      level: SentryLevel.warning,
      withScope: (scope) {
        scope.setTag('error_type', kSentryErrorTypeCreateMeetingTimeout);
        scope.setTag('create_room_flow', flow);
        scope.setTag('timeout_sec', timeout.inSeconds.toString());
        if (meetingType != null) {
          scope.setTag('meeting_type', meetingType.name);
        }
        if (hasSession != null) {
          scope.setTag('has_session', hasSession.toString());
        }

        scope.setContexts('create_meeting_details', {
          'flow': flow,
          'kind': 'client_timeout',
          'timeout_sec': timeout.inSeconds.toString(),
          if (meetingNameLength != null)
            'meeting_name_length': meetingNameLength.toString(),
          if (hasSession != null) 'has_session': hasSession.toString(),
        });
      },
    ),
  );
}
