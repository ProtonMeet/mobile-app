import 'package:meet/helper/extension/response_error.extension.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/rust/errors.dart';

/// Payload shape for [MeetCoreError::ServiceError] from `rust/crates/frb/src/errors.rs`.
const String kMeetCoreServiceErrorHeader = 'MeetCoreError::ServiceError';

// TODO: later to check the rust layer error enum
bool _textIndicatesMissingUserState(String text) {
  return text.contains('No active user') ||
      text.contains('NoActiveUser') ||
      text.contains('No user keys') ||
      text.contains('No primary address');
}

extension BridgeErrorExtension on BridgeError {
  String get userMessage => switch (this) {
    BridgeError_ApiResponse(:final field0) => field0.error,
    BridgeError_MeetCore(:final field0) => meetCoreServiceMessageLine(field0),
    _ => toString(),
  };

  String get detailMessage => switch (this) {
    BridgeError_ApiResponse(:final field0) => field0.detailString,
    BridgeError_MeetCore(:final field0) => field0,
    _ => toString(),
  };

  /// Rust `details` field for a meet-core service error (create meeting, etc.).
  String? get meetCoreServiceDetails => switch (this) {
    BridgeError_MeetCore(:final field0) => parseMeetCoreServiceErrorDetails(
      field0,
    ),
    _ => null,
  };

  /// True when meet-core reports missing active user, keys, or primary address.
  bool get isMissingUserState => _textIndicatesMissingUserState(toString());
}

/// Same as [BridgeError.isMissingUserState] for non-bridge errors (uses [Object.toString]).
bool isMissingUserStateError(Object error) {
  if (error is BridgeError) {
    return error.isMissingUserState;
  }
  return _textIndicatesMissingUserState(error.toString());
}

/// First line `message: …` from [kMeetCoreServiceErrorHeader] payloads; otherwise [payload].
String meetCoreServiceMessageLine(String payload) {
  if (!payload.contains(kMeetCoreServiceErrorHeader)) {
    return payload;
  }
  const prefix = 'message: ';
  final start = payload.indexOf(prefix);
  if (start == -1) {
    return payload;
  }
  final from = start + prefix.length;
  final end = payload.indexOf('\n', from);
  if (end == -1) {
    return payload.substring(from).trim();
  }
  return payload.substring(from, end).trim();
}

/// `details:` line from [kMeetCoreServiceErrorHeader] payloads (Rust `MeetCoreError::ServiceError.details`).
String? parseMeetCoreServiceErrorDetails(String payload) {
  if (!payload.contains(kMeetCoreServiceErrorHeader)) {
    return null;
  }
  const marker = '\ndetails: ';
  final i = payload.indexOf(marker);
  if (i == -1) {
    return null;
  }
  return payload.substring(i + marker.length).trim();
}

/// Extracts a human-readable error message from any error object.
///
/// If [error] is a [BridgeError_ApiResponse], returns the API error string.
/// Otherwise returns [error.toString()].
String extractErrorMessage(Object error) {
  if (error is BridgeError) return error.userMessage;
  return error.toString();
}

/// Logs an error with the appropriate level, automatically extracting
/// a detailed message from [BridgeError_ApiResponse] when applicable.
void logBridgeError(
  String tag,
  String context,
  Object error, {
  StackTrace? stackTrace,
  bool isWarning = false,
}) {
  final message = error is BridgeError ? error.detailMessage : error.toString();

  final formatted = '[$tag] $context: $message';

  if (isWarning) {
    l.logger.w(formatted, error: error, stackTrace: stackTrace);
  } else {
    l.logger.e(formatted, error: error, stackTrace: stackTrace);
  }
}
