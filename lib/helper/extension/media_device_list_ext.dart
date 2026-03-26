import 'package:livekit_client/livekit_client.dart';

extension MediaDeviceListExtension on List<MediaDevice> {
  /// Finds a device by its device ID.
  ///
  /// Returns the device matching the given [deviceId], or null if not found.
  MediaDevice? findByDeviceId(String deviceId) {
    try {
      return firstWhere((d) => d.deviceId == deviceId);
    } catch (e) {
      return null;
    }
  }
}
