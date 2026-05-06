import 'package:meet/helper/extension/response_error.extension.dart';
import 'package:meet/rust/errors.dart';

/// Proton / Muon session and auth-related views of [BridgeError] (aligned with wallet-app
// ignore: comment_references
/// [parseSessionExpireError] and related handling).
extension BridgeErrorSessionExtension on BridgeError {
  /// Message when the user must sign in again, or `null` if this error is not session-related.
  String? get sessionExpireMessage => maybeMap(
    muonAuthSession: (e) => e.field0,
    muonAuthRefresh: (e) => e.field0,
    apiResponse: (e) =>
        e.field0.indicatesSessionInvalidForLogout ? e.field0.error : null,
    orElse: () => null,
  );

  /// Parsed API error when this is [BridgeError_ApiResponse]; otherwise `null`.
  ResponseError? get apiResponseError =>
      maybeMap(apiResponse: (e) => e.field0, orElse: () => null);

  /// Whether this is a Muon client connectivity-style error.
  bool get isMuonClientError =>
      maybeMap(muonClient: (_) => true, orElse: () => false);
}
