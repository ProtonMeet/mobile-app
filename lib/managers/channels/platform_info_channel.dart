import 'package:flutter/services.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/managers/app.state.manager.dart';
import 'package:meet/managers/manager.factory.dart';

class PlatformInfoChannel {
  static const MethodChannel _channel = MethodChannel(
    'me.proton.meet/platform.info',
  );

  /// Check if the app is running from TestFlight (iOS only)
  static Future<bool> isFromTestFlight() async {
    if (!iOS) {
      return false;
    }
    try {
      final bool result = await _channel.invokeMethod('isFromTestFlight');
      return result;
    } catch (e) {
      // If method not implemented or error, assume not from TestFlight
      return false;
    }
  }

  /// True when an iOS app is running on macOS (iOS-on-Mac).
  static Future<bool> isIOSAppOnMacOS() async {
    if (!iOS) {
      return false;
    }
    try {
      final bool result = await _channel.invokeMethod('isIOSAppOnMacOS');
      return result;
    } catch (e) {
      // If method not implemented or error, assume false.
      return false;
    }
  }

  /// Check if the app is in force upgrade state
  static bool isInForceUpgradeState() {
    try {
      final appStateManager = ManagerFactory().get<AppStateManager>();
      final currentState = appStateManager.state;
      return currentState is AppForceUpgradeState;
    } catch (e) {
      return false;
    }
  }
}
