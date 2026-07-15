import 'dart:async';

import 'package:meet/helper/extension/bridge_error.extension.dart';
import 'package:meet/rust/errors.dart';
import 'package:sentry/sentry.dart';

/// Fixed [Sentry] tag value for grouping waiting-room failures.
const String kSentryErrorTypeWaitingRoomFailed = 'waiting_room_failed';

/// Fixed [Sentry] tag value for client-side waiting-room admission timeouts.
const String kSentryErrorTypeWaitingRoomTimeout = 'waiting_room_timeout';

/// Fixed [Sentry] tag value when the host receives too many expired join requests.
const String kSentryErrorTypeWaitingRoomExpiredJoinRequests =
    'waiting_room_expired_join_requests';

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

void _attachWaitingRoomErrorContexts(dynamic scope, Object error) {
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
  } else if (error is BridgeError_WaitingRoomJoinRequestNotFound) {
    scope.setContexts('waiting_room_error', {
      'kind': 'join_request_not_found',
    });
  } else if (error is BridgeError_WaitingRoomJoinCancelled) {
    scope.setContexts('waiting_room_error', {
      'kind': 'join_cancelled',
    });
  } else if (error is BridgeError_MeetCoreAny) {
    scope.setContexts('meet_core_any_error', {'message': error.field0});
  }
}

void _attachWaitingRoomScopeTags(
  dynamic scope, {
  required String flow,
  String? phase,
  String? meetLinkName,
  String? requestId,
  String? participantUid,
}) {
  scope.setTag('error_type', kSentryErrorTypeWaitingRoomFailed);
  scope.setTag('waiting_room_flow', flow);
  if (phase != null) {
    scope.setTag('waiting_room_phase', phase);
  }
  if (meetLinkName != null && meetLinkName.isNotEmpty) {
    scope.setTag('meeting_link_name', meetLinkName);
  }
  if (requestId != null && requestId.isNotEmpty) {
    scope.setTag('waiting_room_request_id', requestId);
  }
  if (participantUid != null && participantUid.isNotEmpty) {
    scope.setTag('waiting_room_participant_uid', participantUid);
  }
}

/// Returns true for user-initiated or expected races that should not hit Sentry.
bool shouldSkipWaitingRoomSentryReport(Object error) {
  if (isWaitingRoomJoinCancelledError(error)) {
    return true;
  }
  if (error is BridgeError_WaitingRoomJoinRequestNotFound) {
    return true;
  }
  return false;
}

/// Report waiting-room failures to Sentry (non-blocking).
void captureWaitingRoomFailureToSentry({
  required String flow,
  required Object error,
  StackTrace? stackTrace,
  String? phase,
  String? meetLinkName,
  String? requestId,
  String? participantUid,
  SentryLevel level = SentryLevel.error,
}) {
  if (shouldSkipWaitingRoomSentryReport(error)) {
    return;
  }

  final st = stackTrace ?? (error is Error ? error.stackTrace : null);
  _enqueueSentryReport(
    () => Sentry.captureException(
      error,
      stackTrace: st,
      withScope: (scope) {
        _attachWaitingRoomScopeTags(
          scope,
          flow: flow,
          phase: phase,
          meetLinkName: meetLinkName,
          requestId: requestId,
          participantUid: participantUid,
        );
        scope.level = level;

        scope.setContexts('waiting_room_details', {
          'flow': flow,
          if (phase != null) 'phase': phase,
          'error_runtime_type': error.runtimeType.toString(),
          'error_message': extractErrorMessage(error),
          if (requestId != null && requestId.isNotEmpty) 'request_id': requestId,
          if (participantUid != null && participantUid.isNotEmpty)
            'participant_uid': participantUid,
        });

        _attachWaitingRoomErrorContexts(scope, error);
      },
    ),
  );
}

/// Guest admission countdown expired (non-blocking).
void captureWaitingRoomTimeoutToSentry({
  required String flow,
  required Duration timeout,
  String? meetLinkName,
  String? requestId,
}) {
  _enqueueSentryReport(
    () => Sentry.captureMessage(
      'Waiting room admission timed out after ${timeout.inSeconds}s (flow: $flow)',
      level: SentryLevel.warning,
      withScope: (scope) {
        scope.setTag('error_type', kSentryErrorTypeWaitingRoomTimeout);
        scope.setTag('waiting_room_flow', flow);
        scope.setTag('timeout_sec', timeout.inSeconds.toString());
        if (meetLinkName != null && meetLinkName.isNotEmpty) {
          scope.setTag('meeting_link_name', meetLinkName);
        }
        if (requestId != null && requestId.isNotEmpty) {
          scope.setTag('waiting_room_request_id', requestId);
        }

        scope.setContexts('waiting_room_details', {
          'flow': flow,
          'kind': 'client_timeout',
          'timeout_sec': timeout.inSeconds.toString(),
          if (requestId != null && requestId.isNotEmpty) 'request_id': requestId,
        });
      },
    ),
  );
}

/// Host received more expired waiting-room join requests than the configured
/// threshold (possible device clock skew). Non-blocking.
void captureExpiredWaitingRoomJoinRequestsThresholdToSentry({
  required int expiredCount,
  required int threshold,
  required String requestId,
  required String participantUid,
  DateTime? expiresAt,
  String? meetLinkName,
}) {
  _enqueueSentryReport(
    () => Sentry.captureMessage(
      'Host received $expiredCount expired waiting-room join requests '
      '(threshold: $threshold)',
      level: SentryLevel.warning,
      withScope: (scope) {
        scope.setTag('error_type', kSentryErrorTypeWaitingRoomExpiredJoinRequests);
        scope.setTag('waiting_room_flow', 'host_expired_join_request_threshold');
        scope.setTag('expired_count', expiredCount.toString());
        scope.setTag('expired_threshold', threshold.toString());
        if (meetLinkName != null && meetLinkName.isNotEmpty) {
          scope.setTag('meeting_link_name', meetLinkName);
        }
        if (requestId.isNotEmpty) {
          scope.setTag('waiting_room_request_id', requestId);
        }
        if (participantUid.isNotEmpty) {
          scope.setTag('waiting_room_participant_uid', participantUid);
        }

        scope.setContexts('waiting_room_details', {
          'kind': 'expired_join_request_threshold_exceeded',
          'expired_count': expiredCount,
          'threshold': threshold,
          'latest_request_id': requestId,
          'latest_participant_uid': participantUid,
          if (expiresAt != null)
            'latest_expires_at': expiresAt.toUtc().toIso8601String(),
          'client_now': DateTime.now().toUtc().toIso8601String(),
        });
      },
    ),
  );
}
