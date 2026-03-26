# macOS Permission Handler

This module provides native permission handling for macOS camera and microphone access. It creates a bridge between your Flutter app and macOS AVFoundation to properly request and check permissions.

## Files Structure

- `macos_permission_handler.dart` - Dart side of the permission handler, using method channels
- `permission_service.dart` - Platform-agnostic service for handling permissions
- `register_macos_permissions.dart` - Utility to register the macOS permission handler

## Native Implementation

- `MacOSPermissionHandler.swift` - Native Swift implementation of permission handling
- AppDelegate registration for the plugin

## Usage

### Basic Usage

```dart
import 'package:your_app/permissions/permission_service.dart';

// Get the singleton instance
final permissionService = PermissionService();

// Request permissions
Future<void> requestPermissions() async {
  // Check individual permissions
  final hasCameraPermission = await permissionService.hasCameraPermission();
  final hasMicrophonePermission = await permissionService.hasMicrophonePermission();
  
  // Request individual permissions
  final cameraGranted = await permissionService.requestCameraPermission();
  final microphoneGranted = await permissionService.requestMicrophonePermission();
}
```

### Integration

Make sure to:

1. Register the plugin during app initialization:
```dart
import 'package:your_app/permissions/register_macos_permissions.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PlatformPermissionRegistry.registerPlugins();
  
  runApp(MyApp());
}
```

2. The Info.plist file already has the necessary permission request strings:
```xml
<key>NSCameraUsageDescription</key>
<string>This app needs camera to show video</string>
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone to send voice</string>
```

## Example

Check the `permission_example.dart` file for a complete example of how to use the permission service in a Flutter widget. 