import 'package:flutter/services.dart';
import 'package:proton_denoise/denoise_type.dart';

/// Debug-only offline denoise (Android): MP3/WAV → 48 kHz WAV via plugin pipelines.
class OfflineDenoiseDebugChannel {
  OfflineDenoiseDebugChannel._();

  static const MethodChannel _channel = MethodChannel('me.proton.meet/denoise');

  static Future<bool> isTypeReady(DenoiseType type) async {
    if (type != DenoiseType.rnnoise && type != DenoiseType.dtlnRs) {
      return false;
    }
    try {
      final method = switch (type) {
        DenoiseType.rnnoise => 'isRnnoiseNativeReady',
        DenoiseType.dtlnRs => 'isDtlnRsNativeReady',
        _ => null,
      };
      if (method == null) {
        return false;
      }
      final ready = await _channel.invokeMethod<bool>(method);
      return ready ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Returns map with `outputPath` (WAV), `sampleRateHz`, and `type`.
  static Future<Map<String, dynamic>> denoiseFile({
    required String inputPath,
    required DenoiseType type,
  }) async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'denoiseDebugAudioFile',
      {'inputPath': inputPath, 'type': type.id},
    );
    if (result == null) {
      throw StateError('denoiseDebugAudioFile returned null');
    }
    return Map<String, dynamic>.from(result);
  }
}
