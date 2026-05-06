import 'package:meet/managers/app.state.manager.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/rust/errors.dart';

/// Routes [BridgeError] session / force-upgrade signals to [AppStateManager].
///
/// Use on values from `catch` around Rust bridge calls so Muon session expiry,
/// token errors, and API 401-style session invalidation trigger the same global
extension BridgeSessionRecoveryExtension on BridgeError {
  /// Returns `true` when this value is a [BridgeError] consumed as session
  /// invalid or force-upgrade.
  bool consumeBridgeSessionIfNeeded() {
    return ManagerFactory().get<AppStateManager>().updateStateFrom(this);
  }
}
