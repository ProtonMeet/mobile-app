import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:universal_io/io.dart';

/// Registers platform-specific plugins
class PlatformPermissionRegistry {
  /// Register the MacOSPermissionHandler plugin for macOS
  static Future<void> registerPlugins() async {
    if (Platform.isMacOS) {
      try {
        // This is just a ping to make sure the plugin is registered
        const channel = MethodChannel('me.proton.meet/macos_permissions');
        await channel.invokeMethod<bool>('hasCameraPermission');
      } on PlatformException catch (e) {
        debugPrint('Error registering macOS permission handler: ${e.message}');
      }
    }
  }
}
