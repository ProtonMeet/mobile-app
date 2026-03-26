import 'package:meet/constants/env.dart';
import 'package:meet/managers/channels/platform.channel.state.dart';
import 'package:meet/models/native.session.model.dart';

abstract class NativeViewChannel {
  Future<void> switchToNativeSignup();
  Future<void> switchToNativeLogin();
  Future<void> restartNative();
  Future<void> initalNativeApiEnv(
    ApiEnv env,
    String appVersion,
    String userAgent,
  );

  /// Add more methods here
  Future<void> switchToUpgrade(FlutterSession session);

  /// logout
  Future<void> nativeLogout();

  /// reports
  Future<void> nativeReportBugs(String username, String email);

  // event stream for native response
  Stream<NativeLoginState> get stream;
}
