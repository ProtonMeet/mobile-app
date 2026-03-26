/// Utilities for parsing Proton Meet join links.
///
/// Supported formats include:
/// - `https://${appConfig.apiEnv.baseUrl}/join/id-XXXX#pwd-YYYY`
/// - `https://${appConfig.apiEnv.baseUrl}/guest/join/id-XXXX#pwd-YYYY`
/// - `https://${appConfig.apiEnv.baseUrl}/u/<any>/join/id-XXXX#pwd-YYYY`
/// - Passcode via fragment `#pwd-YYYY` (or URL-encoded `%23pwd-YYYY`) or query `?pwd=YYYY`
library;

class MeetJoinLinkParseResult {
  final String raw;
  final String trimmed;
  final Uri? uri;

  /// Extracted room id (without the `id-` prefix).
  final String? roomId;

  /// Extracted passcode (without the `pwd-` prefix when present).
  final String? passcode;

  /// Whether input is an `http/https` URL.
  final bool isHttpUrl;

  /// Whether host matches allowed host.
  final bool isAllowedHost;

  const MeetJoinLinkParseResult({
    required this.raw,
    required this.trimmed,
    required this.uri,
    required this.roomId,
    required this.passcode,
    required this.isHttpUrl,
    required this.isAllowedHost,
  });

  bool get isEmpty => trimmed.isEmpty;

  /// Basic sanity rule used by the existing UI.
  bool get looksValidRoomId => roomId != null && roomId!.length >= 6;

  /// Full validation (requires passcode).
  bool get isValid =>
      isHttpUrl &&
      isAllowedHost &&
      looksValidRoomId &&
      passcode != null &&
      passcode!.isNotEmpty;
}

MeetJoinLinkParseResult parseMeetJoinLink(
  String raw, {
  String allowedHost = 'meet.proton.me',
}) {
  final trimmed = raw.trim();
  final uri = Uri.tryParse(trimmed);

  final isHttpUrl =
      uri != null && (uri.scheme == 'https' || uri.scheme == 'http');
  final isAllowedHost = isHttpUrl && uri.host == allowedHost;

  // Room id parsing (accept /join, /guest/join, /u/<any>/join)
  String? roomId;
  if (uri != null) {
    final path = uri.path;
    final idMatch = RegExp(
      '^.*?/(?:join|(?:guest|u/[^/]+)/join)/id-([A-Za-z0-9]+)',
      caseSensitive: false,
    ).firstMatch(path);
    roomId = idMatch?.group(1);
  }

  // Passcode parsing
  String? pass;
  final passcodePattern = RegExp(r'^[A-Za-z0-9]+$');

  // Prefer fragment if available.
  if (uri != null && uri.fragment.isNotEmpty) {
    final frag = uri.fragment;
    // IMPORTANT: only accept fragment passcodes with explicit `pwd-` prefix
    // AND only if the passcode token is strictly alphanumeric.
    final m = RegExp(
      r'^pwd-([A-Za-z0-9]+)$',
      caseSensitive: false,
    ).firstMatch(frag);
    final token = m?.group(1);
    if (token != null && passcodePattern.hasMatch(token)) {
      pass = token;
    }
  }

  // Fallback: fragment could be URL-encoded as %23pwd-...
  pass ??= RegExp(
    r'(?:#|%23)pwd-([A-Za-z0-9]+)(?:$|&)',
    caseSensitive: false,
  ).firstMatch(trimmed)?.group(1);
  if (pass != null && !passcodePattern.hasMatch(pass)) {
    pass = null;
  }

  // Fallback: query parameter.
  if (pass == null && uri != null) {
    final fromQuery = uri.queryParameters['pwd'];
    if (fromQuery != null && fromQuery.isNotEmpty) {
      final token = fromQuery.toLowerCase().startsWith('pwd-')
          ? fromQuery.substring(4)
          : fromQuery;
      if (passcodePattern.hasMatch(token)) {
        pass = token;
      }
    }
  }

  return MeetJoinLinkParseResult(
    raw: raw,
    trimmed: trimmed,
    uri: uri,
    roomId: roomId,
    passcode: pass,
    isHttpUrl: isHttpUrl,
    isAllowedHost: isAllowedHost,
  );
}
