import 'dart:io';
import 'package:flutter/services.dart';
import 'package:meet/helper/logger.dart' as l;

/// Channel for detecting physical key presses on Android
/// Currently supports home key detection, but can be extended for other keys
class PhysicalKeyChannel {
  static const _ch = MethodChannel('me.proton.meet/physical_key');

  static bool get supported => Platform.isAndroid;

  /// Callback when user presses home key
  static Future<void> Function()? onHomeKeyPressed;

  /// Initialize the channel and set up method call handler
  static void initialize({
    required Future<void> Function() onHomeKeyPressedCallback,
  }) {
    if (!supported) {
      return;
    }

    onHomeKeyPressed = onHomeKeyPressedCallback;
    _ch.setMethodCallHandler(_handleMethodCall);
    l.logger.d('[PhysicalKeyChannel] Initialized');
  }

  /// Dispose the channel and clear callback
  static void dispose() {
    if (!supported) {
      return;
    }

    _ch.setMethodCallHandler(null);
    onHomeKeyPressed = null;
    l.logger.d('[PhysicalKeyChannel] Disposed');
  }

  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    try {
      if (call.method == 'onHomeKeyPressed') {
        if (onHomeKeyPressed != null) {
          await onHomeKeyPressed!();
        }
        l.logger.d('[PhysicalKeyChannel] Home key pressed');
        return null;
      }
      throw MissingPluginException('Unknown method: ${call.method}');
    } catch (e) {
      l.logger.e('[PhysicalKeyChannel] Error handling method call: $e');
      return Future.error(e);
    }
  }
}
