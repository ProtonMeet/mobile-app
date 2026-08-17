/// On-device microphone denoising for Proton Meet.
///
/// Import this library only:
/// `import 'package:proton_denoise/proton_denoise.dart';`
///
/// Native I/O is routed through [ProtonDenoiseEffects]. Implementation details
/// live under `lib/src/` and are not part of the public API.
library;

export 'audio_denoise_track_processor.dart';
export 'deepfilter_config.dart';
export 'denoise_models.dart';
export 'denoise_type.dart';

import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'audio_denoise_track_processor.dart';
import 'denoise_models.dart';
import 'denoise_type.dart';
import 'src/denoise_platform.dart';
import 'src/proton_denoise_channel.dart';

/// Entry point for attaching denoise to flutter_webrtc local audio tracks.
///
/// Use [instance] for all native calls. Typical Meet integration:
///
/// ```dart
/// if (!ProtonDenoiseEffects.isSupported) return;
///
/// // Preferred — denoise attaches when the LiveKit mic track starts
/// final processor = ProtonDenoiseEffects.instance.createAudioDenoiseTrackProcessor(
///   type: DenoiseType.rnnoise,
/// );
///
/// // Or attach / detach on an existing WebRTC track id
/// await ProtonDenoiseEffects.instance.attachDenoise(
///   trackId: id,
///   type: DenoiseType.rnnoise,
/// );
/// await ProtonDenoiseEffects.instance.detachDenoise(trackId: id);
/// ```
class ProtonDenoiseEffects {
  ProtonDenoiseEffects._();

  static final ProtonDenoiseEffects instance = ProtonDenoiseEffects._();

  final ProtonDenoiseChannel _channel = ProtonDenoiseChannel();

  /// `true` on iOS, Android, macOS, Linux, and Windows; `false` on web.
  static bool get isSupported => isProtonDenoisePlatformSupported;

  /// Same platforms as [isSupported] — WebRTC track attach pipeline.
  static bool get supportsWebRtcTrackPipeline =>
      isProtonDenoisePlatformSupported;

  /// LiveKit [AudioDenoiseTrackProcessor] sharing this facade's channel client.
  ///
  /// Pass the result to `LocalAudioTrack.create`. Do not construct
  /// [AudioDenoiseTrackProcessor] yourself — it must share this facade's channel.
  AudioDenoiseTrackProcessor createAudioDenoiseTrackProcessor({
    required DenoiseType type,
  }) {
    return AudioDenoiseTrackProcessor(channel: _channel, type: type);
  }

  Future<List<DenoiseTypeInfo>> listDenoiseTypes() =>
      _channel.listDenoiseTypes();

  Future<bool> isTypeReady(DenoiseType type) => _channel.isTypeReady(type);

  /// Per-backend native load probes for debug settings UI.
  Future<List<DenoiseDiagnosticEntry>> diagnoseDenoise() =>
      _channel.diagnoseDenoise();

  /// Like [diagnoseDenoise] but includes fallback/error notes for debug UI.
  Future<DenoiseDiagnosticsResult> diagnoseDenoiseWithStatus() =>
      _channel.diagnoseDenoiseWithStatus();

  /// Production-style warm-up probes per backend (omit [type] to warm all).
  Future<List<DenoiseWarmUpResult>> warmUpDenoise({DenoiseType? type}) =>
      _channel.warmUpDenoise(type: type);

  Future<void> attachDenoise({
    required String trackId,
    required DenoiseType type,
    double? deepFilterAttenLimDb,
  }) => _channel.attachDenoise(
    trackId: trackId,
    type: type,
    deepFilterAttenLimDb: deepFilterAttenLimDb,
  );

  Future<void> setDeepFilterAttenLim({
    required String trackId,
    required double attenLimDb,
  }) =>
      _channel.setDeepFilterAttenLim(trackId: trackId, attenLimDb: attenLimDb);

  Future<void> detachDenoise({required String trackId}) =>
      _channel.detachDenoise(trackId: trackId);
}

/// Low-level RNNoise C API wrapper (desktop tests / frame processing without WebRTC attach).
///
/// On mobile, use [ProtonDenoiseEffects] for in-meeting mic denoise. Linux/Windows
/// register both `me.proton.meet/denoise` and legacy `proton_denoise` channels.
class ProtonDenoise {
  static bool get isSupported => ProtonDenoiseEffects.isSupported;

  static bool get supportsWebRtcCapturePipeline =>
      ProtonDenoiseEffects.supportsWebRtcTrackPipeline;

  ProtonDenoise._();

  static const MethodChannel _channel = MethodChannel('proton_denoise');

  static ProtonDenoise? _instance;
  static ProtonDenoise get instance => _instance ??= ProtonDenoise._();

  Future<void> initialize() async {
    if (!isSupported) return;
    final ok = await _channel.invokeMethod<bool>('create');
    if (ok != true) {
      throw StateError('Failed to create denoise handle');
    }
  }

  Future<void> dispose() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('destroy');
    _instance = null;
  }

  Future<int> get frameSize async {
    if (!isSupported) return 0;
    final size = await _channel.invokeMethod<int>('getFrameSize');
    return size ?? 0;
  }

  Future<void> setEnabled(bool enabled) async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('setEnabled', {'enabled': enabled});
  }

  Future<bool> isEnabled() async {
    if (!isSupported) return false;
    final enabled = await _channel.invokeMethod<bool>('isEnabled');
    return enabled ?? false;
  }

  bool _initialized = false;

  /// Enables RNNoise handle only (no WebRTC attach — use [ProtonDenoiseEffects] + track id).
  Future<void> setCaptureDenoiseEnabled(bool enabled) async {
    if (!isSupported) return;
    if (!_initialized) {
      await initialize();
      _initialized = true;
    }
    await setEnabled(enabled);
  }

  Future<({double vad, Float32List samples})> processFrame(
    Float32List samples, {
    int channels = 1,
  }) async {
    final response = await _channel.invokeMapMethod<String, dynamic>(
      'processFrame',
      {'samples': Float32List.fromList(samples), 'channels': channels},
    );
    if (response == null) {
      throw StateError('processFrame returned null');
    }
    final out = response['samples'] as Float32List;
    final vad = (response['vad'] as num?)?.toDouble() ?? 0;
    return (vad: vad, samples: out);
  }
}
