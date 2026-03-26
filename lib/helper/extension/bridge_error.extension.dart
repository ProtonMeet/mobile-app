import 'package:meet/helper/extension/response_error.extension.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/rust/errors.dart';

extension BridgeErrorExtension on BridgeError {
  String get userMessage => switch (this) {
    BridgeError_ApiResponse(:final field0) => field0.error,
    _ => toString(),
  };

  String get detailMessage => switch (this) {
    BridgeError_ApiResponse(:final field0) => field0.detailString,
    _ => toString(),
  };
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
