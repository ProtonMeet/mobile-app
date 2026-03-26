import 'package:flutter/foundation.dart';
import 'package:meet/managers/manager.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:universal_io/io.dart';

import 'macos_permission_handler.dart';

// Import platform extension for Linux check
bool get isLinux => !kIsWeb && Platform.isLinux;

/// A platform-agnostic service for handling media permissions
class PermissionService implements Manager {
  static final PermissionService _instance = PermissionService._internal();

  /// Singleton instance of the permission service
  factory PermissionService() => _instance;

  /// Private constructor for singleton pattern
  PermissionService._internal();

  /// MacOS permission handler
  final _macOSHandler = MacOSPermissionHandler();

  /// Get camera permission status
  Future<ph.PermissionStatus> cameraStatus() async {
    if (Platform.isMacOS && !kIsWeb) {
      final statusString = await _macOSHandler.cameraStatus();
      return _mapMacOSStatusToPermissionStatus(statusString);
    } else if (isLinux) {
      // Linux doesn't require runtime permissions, assume granted
      return ph.PermissionStatus.granted;
    } else {
      // Use permission_handler for other platforms
      return ph.Permission.camera.status;
    }
  }

  /// Check if camera permission is granted
  Future<bool> hasCameraPermission() async {
    if (Platform.isMacOS && !kIsWeb) {
      return _macOSHandler.hasCameraPermission();
    } else if (isLinux) {
      // Linux doesn't require runtime permissions, assume granted
      return true;
    } else {
      // Use permission_handler for other platforms
      return ph.Permission.camera.isGranted;
    }
  }

  /// Request camera permission
  Future<bool> requestCameraPermission() async {
    if (Platform.isMacOS && !kIsWeb) {
      return _macOSHandler.requestCameraPermission();
    } else if (isLinux) {
      // Linux doesn't require runtime permissions, assume granted
      return true;
    } else {
      // Use permission_handler for other platforms
      final status = await ph.Permission.camera.request();
      return status.isGranted;
    }
  }

  /// Get microphone permission status
  Future<ph.PermissionStatus> microphoneStatus() async {
    if (Platform.isMacOS && !kIsWeb) {
      final statusString = await _macOSHandler.microphoneStatus();
      return _mapMacOSStatusToPermissionStatus(statusString);
    } else if (isLinux) {
      // Linux doesn't require runtime permissions, assume granted
      return ph.PermissionStatus.granted;
    } else {
      // Use permission_handler for other platforms
      return ph.Permission.microphone.status;
    }
  }

  /// Check if microphone permission is granted
  Future<bool> hasMicrophonePermission() async {
    if (Platform.isMacOS && !kIsWeb) {
      return _macOSHandler.hasMicrophonePermission();
    } else if (isLinux) {
      // Linux doesn't require runtime permissions, assume granted
      return true;
    } else {
      // Use permission_handler for other platforms
      return ph.Permission.microphone.isGranted;
    }
  }

  /// Request microphone permission
  Future<bool> requestMicrophonePermission() async {
    if (Platform.isMacOS && !kIsWeb) {
      return _macOSHandler.requestMicrophonePermission();
    } else if (isLinux) {
      // Linux doesn't require runtime permissions, assume granted
      return true;
    } else {
      // Use permission_handler for other platforms
      final status = await ph.Permission.microphone.request();
      return status.isGranted;
    }
  }

  /// Request both camera and microphone permissions
  Future<Map<String, bool>> requestMediaPermissions() async {
    final cameraGranted = await requestCameraPermission();
    final microphoneGranted = await requestMicrophonePermission();

    return {'camera': cameraGranted, 'microphone': microphoneGranted};
  }

  /// Check if share screen capture permission is granted
  Future<bool> hasShareScreenCapturePermission() async {
    if (Platform.isMacOS && !kIsWeb) {
      return _macOSHandler.hasShareScreenCapturePermission();
    }
    return true;
  }

  /// Request share screen capture permission
  Future<bool> requestShareScreenCapturePermission() async {
    if (Platform.isMacOS && !kIsWeb) {
      return _macOSHandler.requestShareScreenCapturePermission();
    }
    return true;
  }

  @override
  Future<void> dispose() async {}

  @override
  Priority getPriority() {
    return Priority.level1;
  }

  @override
  Future<void> init() async {}

  @override
  Future<void> login(String userID) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<void> reload() async {}

  /// Map macOS authorization status string to PermissionStatus
  ph.PermissionStatus _mapMacOSStatusToPermissionStatus(String statusString) {
    switch (statusString) {
      case 'authorized':
        return ph.PermissionStatus.granted;
      case 'denied':
        return ph.PermissionStatus.denied;
      case 'restricted':
        // Restricted means permanently denied (e.g., parental controls)
        return ph.PermissionStatus.permanentlyDenied;
      case 'notDetermined':
        // Not asked yet, treat as denied
        return ph.PermissionStatus.denied;
      default:
        return ph.PermissionStatus.denied;
    }
  }
}
