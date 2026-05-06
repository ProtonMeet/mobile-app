import 'package:meet/rust/errors.dart';

/// HTTP / API numeric signals that mean the client must upgrade.
///
/// - [5003] / [5005]: Proton Meet force-upgrade responses (confirm with backend).
const Set<int> protonForceUpgradeResponseCodes = {5003, 5005};

/// Substrings in [ResponseError.error] / [ResponseError.details]; keep specific to avoid false positives.
const List<String> _forceUpgradeTextHints = [];

extension ResponseErrorExtension on ResponseError {
  String get detailString {
    return 'ResponseError:\n  Code: $code\n  Error: $error\n  Details: $details';
  }

  /// HTTP [code] or body text that indicates the session is no longer valid and the user
  /// should be signed out (refresh failed, revoked session, etc.).
  ///
  /// [code] is the HTTP status when mapped from [MeetCoreError::HttpClientError] in Rust.
  bool get indicatesSessionInvalidForLogout {
    if (code == 401) {
      return true;
    }
    if (error.isEmpty && details.isEmpty) {
      return false;
    }
    final haystack = '${error.toLowerCase()} ${details.toLowerCase()}';
    return haystack.contains('invalid authentication') ||
        haystack.contains('invalid grant') ||
        haystack.contains('token expired') ||
        haystack.contains('session expired') ||
        haystack.contains('session invalid') ||
        haystack.contains('access token does not have sufficient scope');
  }

  /// True when the API indicates the client must upgrade (e.g. `/tests/ping`, feature flags).
  ///
  /// Uses [protonForceUpgradeResponseCodes] first, then conservative [error] / [details] hints.
  bool get indicatesForceUpgrade {
    if (protonForceUpgradeResponseCodes.contains(code)) {
      return true;
    }
    if (error.isEmpty && details.isEmpty) {
      return false;
    }
    final haystack = '${error.toLowerCase()} ${details.toLowerCase()}';
    for (final hint in _forceUpgradeTextHints) {
      if (haystack.contains(hint)) {
        return true;
      }
    }
    return false;
  }
}
