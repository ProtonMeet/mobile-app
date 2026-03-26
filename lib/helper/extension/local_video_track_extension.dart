import 'package:livekit_client/livekit_client.dart';

/// Helper class for creating LocalVideoTrack instances
class LocalVideoTrackHelper {
  /// Creates a camera track with optional device or position
  ///
  /// If [device] is provided, uses that device.
  /// If [position] is provided (and device is null), uses that camera position.
  /// Otherwise, uses the default camera.
  static Future<LocalVideoTrack> cameraTrack({
    required VideoParameters parameters,
    MediaDevice? device,
    CameraPosition? position,
  }) async {
    if (device != null) {
      return LocalVideoTrack.createCameraTrack(
        CameraCaptureOptions(deviceId: device.deviceId, params: parameters),
      );
    } else if (position != null) {
      return LocalVideoTrack.createCameraTrack(
        CameraCaptureOptions(cameraPosition: position, params: parameters),
      );
    }
    return LocalVideoTrack.createCameraTrack(
      CameraCaptureOptions(params: parameters),
    );
  }
}
