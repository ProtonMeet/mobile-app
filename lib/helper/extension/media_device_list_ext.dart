// ignore_for_file: experimental_member_use

import 'package:audio_session/audio_session.dart';
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

/// Extension to check if the audio device type is a headset.
///
/// Note: AudioDeviceType is experimental and may change in future versions.
/// This mapping is based on current known behaviors and should be reviewed
/// when updating the underlying audio plugin.
extension AudioDeviceTypeX on AudioDeviceType {
  bool get isExternalAudioOutput {
    switch (this) {
      case AudioDeviceType.wiredHeadset:
      case AudioDeviceType.wiredHeadphones:
      case AudioDeviceType.bluetoothA2dp:
      case AudioDeviceType.bluetoothSco:
      case AudioDeviceType.hearingAid:
        return true;
      default:
        return false;
    }
  }

  bool get isBluetoothAudioOutput {
    switch (this) {
      case AudioDeviceType.bluetoothA2dp:
      case AudioDeviceType.bluetoothSco:
        return true;
      default:
        return false;
    }
  }
}
