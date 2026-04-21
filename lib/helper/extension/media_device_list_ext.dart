import 'package:livekit_client/livekit_client.dart';

extension MediaDeviceIterableExtension on Iterable<MediaDevice> {
  /// Heuristic from device [MediaDevice.label]: headphones, headset, Bluetooth, etc.
  bool get hasLabelSuggestingExternalAudioOutput =>
      any(_labelSuggestsExternalAudioOutput);
}

bool _labelSuggestsExternalAudioOutput(MediaDevice device) {
  final label = device.label.toLowerCase();
  const keywords = [
    'headphone',
    'headset',
    'bluetooth',
    'wireless',
    'airpods',
    'buds',
    'beats',
    'sony',
    'jbl',
    'anker',
    'soundcore',
    'usb audio',
    'usb headset',
    'hands-free',
    'a2dp',
  ];

  return keywords.any(label.contains);
}

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
