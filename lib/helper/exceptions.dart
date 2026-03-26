// import 'package:flutter/widgets.dart';
// import 'package:meet/helper/extension/response.error.extension.dart';
// import 'package:meet/l10n/generated/locale.dart';
// import 'package:meet/rust/errors.dart';

// extension BridgeErrorExt on BridgeError {
//   /// this will be used after refactor how handle context
//   String getLocalizedMessage(BuildContext context) {
//     /// A shorthand for localization access if needed
//     final s = S.of(context);

//     /// `map` will call the function for the specific subtype of `BridgeError`
//     ///    map will show error if new type added but didnt handle
//     return map(
//       apiLock: (e) => s.bridge_error_api_lock,
//       generic: (e) => s.bridge_error_generic,
//       muonAuthSession: (e) => s.session_expired_content,
//       muonAuthRefresh: (e) => s.session_expired_content,
//       muonClient: (e) => s.bridge_error_muon_client,
//       muonSession: (e) => s.bridge_error_muon_client,
//       apiResponse: (e) => e.field0.error,
//       walletCrypto: (e) => s.bridge_error_wallet_crypto,
//       walletDecryption: (e) => s.bridge_error_wallet_decryption,
//       login: (e) => s.bridge_error_login,
//       fork: (e) => s.bridge_error_fork,
//       apiDeserialize: (e) => s.bridge_error_api_deserialize,
//       bitcoinDeserialize: (e) => s.bridge_error_bitcoin_deserialize,
//       encoding: (e) => s.bridge_error_encoding,
//     );
//   }

//   String get localizedString {
//     /// `map` will call the function for the specific subtype of `BridgeError`
//     ///    map will show error if new type added but didnt handle
//     return map(
//       apiLock: (e) {
//         return "Failed to initialize the Proton API. Please relaunch the app.";
//       },
//       generic: (e) {
//         return "An unexpected error occurred. Please try again.";
//       },
//       muonAuthSession: (e) {
//         return "Your session has expired. Please log in to continue.";
//       },
//       muonAuthRefresh: (e) {
//         return "Your session has expired. Please log in to continue.";
//       },
//       muonClient: (e) {
//         // Possibly a more specific message, or just a fallback for network issues
//         return "A network error occurred in Muon. Please try again.";
//       },
//       muonSession: (e) {
//         return "A Muon session error occurred. Please try again.";
//       },
//       apiResponse: (e) {
//         return e.field0.error;
//       },
//       walletCrypto: (e) {
//         return "A wallet cryptography error occurred. Please try again.";
//       },
//       walletDecryption: (e) {
//         return "Failed to decrypt wallet. Please try again.";
//       },
//       login: (e) {
//         return "Login failed. Please check your credentials and try again.";
//       },
//       fork: (e) {
//         return "Failed to fork the session. Please try again.";
//       },
//       apiDeserialize: (e) {
//         return "Failed to parse the server response. Please try again.";
//       },
//       bitcoinDeserialize: (e) {
//         return "Failed to parse the Bitcoin server response. Please try again.";
//       },
//       encoding: (e) {
//         return "String encoding error. Please try again.";
//       },
//     );
//   }
// }

// ResponseError? parseResponseError(BridgeError exception) {
//   return exception.maybeMap(
//     apiResponse: (e) => e.field0,
//     orElse: () => null,
//   );
// }

// String parseSampleDisplayError(BridgeError exception) {
//   return exception.map(
//     apiLock: (e) => e.field0,
//     generic: (e) => e.field0,
//     muonAuthSession: (e) => e.field0,
//     muonAuthRefresh: (e) => e.field0,
//     muonClient: (e) => e.field0,
//     muonSession: (e) => e.field0,
//     apiResponse: (e) => e.field0.error,
//     walletCrypto: (e) => e.field0,
//     walletDecryption: (e) => e.field0,
//     login: (e) => e.field0,
//     fork: (e) => e.field0,
//     apiDeserialize: (e) => e.field0,
//     bitcoinDeserialize: (e) => e.field0,
//     encoding: (e) => e.field0,
//   );
// }

// bool ifMuonClientError(BridgeError exception) {
//   return exception.maybeMap(
//     muonClient: (e) => true,
//     orElse: () => false,
//   );
// }

// String? parseAppCryptoError(BridgeError exception) {
//   return exception.maybeMap(
//     walletDecryption: (e) => e.field0,
//     orElse: () => null,
//   );
// }

// String? parseSessionExpireError(BridgeError exception) {
//   return exception.maybeMap(
//     muonAuthSession: (e) => e.field0,
//     muonAuthRefresh: (e) => e.field0,
//     orElse: () => null,
//   );
// }

// String? parseUserLimitationError(BridgeError exception) {
//   final responseError = parseResponseError(exception);
//   if (responseError != null && responseError.isCreationLimition()) {
//     return responseError.error;
//   }
//   return null;
// }
