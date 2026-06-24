import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/rust/proton_meet/desktop_web_login.dart';
import 'package:meet/rust/proton_meet/models/desktop_web_login.dart';
import 'package:meet/rust/proton_meet/models/proton_user_session.dart';

/// Ephemeral desktop web login session. Create when opening the login UI;
/// call [cancel] or let it go out of scope when done.
class DesktopWebLoginManager {
  DesktopWebLoginManager._(this._login);

  final DesktopWebLogin _login;

  static Future<DesktopWebLoginManager> create(
    AppCoreManager appCoreManager,
  ) async {
    final userAgent = appCoreManager.userAgent;
    final login = await DesktopWebLogin.newInstance(
      env: appCoreManager.env.toString(),
      appVersion: await userAgent.appVersion,
      userAgent: await userAgent.ua,
      httpHost: appCoreManager.env.httpHost,
      app: appCoreManager.appCore,
    );
    return DesktopWebLoginManager._(login);
  }

  Future<DesktopWebLoginStart> start({required String childClientId}) =>
      _login.start(childClientId: childClientId);

  Future<ProtonUserSession?> poll() => _login.poll();

  Future<void> cancel() => _login.cancel();
}
