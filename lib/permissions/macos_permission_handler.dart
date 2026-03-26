import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:universal_io/io.dart';

/// A class to handle macOS permissions for camera and microphone
class MacOSPermissionHandler {
  static const _channel = MethodChannel('me.proton.meet/macos_permissions');

  /// Singleton instance
  static final MacOSPermissionHandler _instance =
      MacOSPermissionHandler._internal();

  /// Factory constructor to return the singleton instance
  factory MacOSPermissionHandler() => _instance;

  /// Private constructor for singleton pattern
  MacOSPermissionHandler._internal();

  /// Check if camera permission is granted
  ///
  /// Returns a [Future] with the permission status as a [bool]
  Future<bool> hasCameraPermission() async {
    if (!_isMacOS) return false;
    try {
      return await _channel.invokeMethod<bool>('hasCameraPermission') ?? false;
    } on PlatformException catch (e) {
      debugPrint('Error checking camera permission: ${e.message}');
      return false;
    }
  }

  /// Get camera permission status
  ///
  /// Returns a [Future] with the permission status as a [String]
  /// Possible values: "notDetermined", "restricted", "denied", "authorized"
  Future<String> cameraStatus() async {
    if (!_isMacOS) return 'denied';
    try {
      return await _channel.invokeMethod<String>('cameraStatus') ?? 'denied';
    } on PlatformException catch (e) {
      debugPrint('Error getting camera permission status: ${e.message}');
      return 'denied';
    }
  }

  /// Request camera permission
  ///
  /// Returns a [Future] with the permission status as a [bool]
  Future<bool> requestCameraPermission() async {
    if (!_isMacOS) return false;
    try {
      return await _channel.invokeMethod<bool>('requestCameraPermission') ??
          false;
    } on PlatformException catch (e) {
      debugPrint('Error requesting camera permission: ${e.message}');
      return false;
    }
  }

  /// Check if microphone permission is granted
  ///
  /// Returns a [Future] with the permission status as a [bool]
  Future<bool> hasMicrophonePermission() async {
    if (!_isMacOS) return false;
    try {
      return await _channel.invokeMethod<bool>('hasMicrophonePermission') ??
          false;
    } on PlatformException catch (e) {
      debugPrint('Error checking microphone permission: ${e.message}');
      return false;
    }
  }

  /// Get microphone permission status
  ///
  /// Returns a [Future] with the permission status as a [String]
  /// Possible values: "notDetermined", "restricted", "denied", "authorized"
  Future<String> microphoneStatus() async {
    if (!_isMacOS) return 'denied';
    try {
      return await _channel.invokeMethod<String>('microphoneStatus') ??
          'denied';
    } on PlatformException catch (e) {
      debugPrint('Error getting microphone permission status: ${e.message}');
      return 'denied';
    }
  }

  /// Request microphone permission
  ///
  /// Returns a [Future] with the permission status as a [bool]
  Future<bool> requestMicrophonePermission() async {
    if (!_isMacOS) return false;
    try {
      return await _channel.invokeMethod<bool>('requestMicrophonePermission') ??
          false;
    } on PlatformException catch (e) {
      debugPrint('Error requesting microphone permission: ${e.message}');
      return false;
    }
  }

  /// Check if share screen capture permission is granted
  ///
  /// Returns a [Future] with the permission status as a [bool]
  Future<bool> hasShareScreenCapturePermission() async {
    if (!_isMacOS) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'hasShareScreenCapturePermission',
          ) ??
          false;
    } on PlatformException catch (e) {
      debugPrint(
        'Error checking share screen capture permission: ${e.message}',
      );
      return false;
    }
  }

  /// Request share screen capture permission
  ///
  /// Returns a [Future] with the permission status as a [bool]
  Future<bool> requestShareScreenCapturePermission() async {
    if (!_isMacOS) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'requestShareScreenCapturePermission',
          ) ??
          false;
    } on PlatformException catch (e) {
      debugPrint(
        'Error requesting share screen capture permission: ${e.message}',
      );
      return false;
    }
  }

  /// Checks if the current platform is macOS
  bool get _isMacOS => Platform.isMacOS;
}
