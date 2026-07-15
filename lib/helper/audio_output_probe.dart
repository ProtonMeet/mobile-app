// ignore_for_file: experimental_member_use

import 'package:audio_session/audio_session.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/helper/extension/media_device_list_ext.dart';
import 'package:meet/helper/logger.dart' as l;

typedef AudioOutputCapabilities = ({
  bool hasExternal,
  bool hasBluetooth,
});

/// Detects external and Bluetooth audio outputs from hardware labels and
/// [AudioSession] device types.
class AudioOutputProbe {
  AudioOutputProbe._();

  /// Combines a hardware label heuristic with [AudioSession] device types.
  static Future<AudioOutputCapabilities> detect({
    required bool labelSuggestsExternal,
  }) async {
    final session = await _probeAudioSession();
    return (
      hasExternal: labelSuggestsExternal || session.hasExternal,
      hasBluetooth: session.hasBluetooth,
    );
  }

  static Future<AudioOutputCapabilities> detectFromSpeakerDevices(
    Iterable<MediaDevice> speakerDevices,
  ) {
    return detect(
      labelSuggestsExternal:
          speakerDevices.hasLabelSuggestingExternalAudioOutput,
    );
  }

  static Future<AudioOutputCapabilities> _probeAudioSession() async {
    try {
      final audioSession = await AudioSession.instance;
      final devices = await audioSession.getDevices();
      return (
        hasExternal: devices.any((device) => device.type.isExternalAudioOutput),
        hasBluetooth:
            devices.any((device) => device.type.isBluetoothAudioOutput),
      );
    } catch (e) {
      l.logger.w('[AudioOutputProbe] Error checking audio session: $e');
      return (hasExternal: false, hasBluetooth: false);
    }
  }
}
