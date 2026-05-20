import 'package:meet/managers/secure.storage/secure.storage.manager.dart';
import 'package:meet/models/native.session.model.dart';

/// Builds [FlutterSession] from secure storage for
/// `native.navigation.plan.*` method-channel calls (Android / iOS native IAP).
Future<FlutterSession?> flutterSessionForNativePlansChannel(
  SecureStorageManager storage,
) async {
  final userId = await storage.get('userId');
  final sessionId = await storage.get('sessionId');
  final accessToken = await storage.get('accessToken');
  final refreshToken = await storage.get('refreshToken');
  final scopesStr = await storage.get('scopes');
  if (userId.isEmpty ||
      sessionId.isEmpty ||
      accessToken.isEmpty ||
      refreshToken.isEmpty ||
      scopesStr.isEmpty) {
    return null;
  }
  final userName = await storage.get('userName');
  final passphrase = await storage.get('userPassphrase');
  final scopes = scopesStr
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  return FlutterSession(
    userId: userId,
    sessionId: sessionId,
    userName: userName.isNotEmpty ? userName : userId,
    passphrase: passphrase,
    accessToken: accessToken,
    refreshToken: refreshToken,
    scopes: scopes,
  );
}
