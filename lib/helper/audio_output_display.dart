import 'package:flutter/widgets.dart';
import 'package:meet/constants/assets.gen.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

/// Centralized rules for picking the audio-output icon / label based on the
/// current speaker / external / bluetooth flags.
///
/// Used by:
/// - Speaker toggle button (room top bar, prejoin video preview button)
/// - Speaker phone bottom sheet panels (room + prejoin)
///
/// Priority for the toggle [icon]:
///   isSpeakerPhone -> speakerphone
///   else -> [defaultDeviceIcon]
///
/// Priority for the default-device menu item ([defaultDeviceIcon] / [defaultDeviceLabel]):
///   hasExternalAudioOutput && hasBluetoothAudioOutput -> bluetooth
///   hasExternalAudioOutput                            -> headphones
///   else                                              -> phone earpiece
class AudioOutputDisplay {
  const AudioOutputDisplay._();

  /// Icon for the speaker toggle button (reflects the currently active output).
  static SvgGenImage icon(
    BuildContext context, {
    required bool isSpeakerPhone,
    required bool hasExternalAudioOutput,
    required bool hasBluetoothAudioOutput,
  }) {
    if (isSpeakerPhone) {
      return context.images.iconAudioOutputSpeakerphone;
    }
    return defaultDeviceIcon(
      context,
      hasExternalAudioOutput: hasExternalAudioOutput,
      hasBluetoothAudioOutput: hasBluetoothAudioOutput,
    );
  }

  /// Icon for the "default device" menu item in the speaker-phone panel.
  static SvgGenImage defaultDeviceIcon(
    BuildContext context, {
    required bool hasExternalAudioOutput,
    required bool hasBluetoothAudioOutput,
  }) {
    if (hasExternalAudioOutput) {
      return hasBluetoothAudioOutput
          ? context.images.iconAudioOutputBluetooth
          : context.images.iconAudioOutputHeadphones;
    }
    return context.images.iconAudioOutputPhone;
  }

  /// Localized label for the "default device" menu item in the speaker-phone panel.
  static String defaultDeviceLabel(
    BuildContext context, {
    required bool hasExternalAudioOutput,
    required bool hasBluetoothAudioOutput,
  }) {
    if (hasExternalAudioOutput) {
      return hasBluetoothAudioOutput
          ? context.local.audio_output_bluetooth_device
          : context.local.audio_output_headphones;
    }
    return context.local.audio_output_earpiece;
  }
}
