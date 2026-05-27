/// On-device microphone denoising (RNNoise; DeepFilter stub).
library;

export 'audio_denoise_track_processor.dart';
export 'proton_denoise_channel.dart';
export 'src/denoise_type.dart';

import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'proton_denoise_channel.dart';
import 'src/denoise_platform.dart';
import 'src/denoise_type.dart';

/// Facade for attaching denoise to flutter_webrtc local audio tracks.
class ProtonDenoiseEffects {
  ProtonDenoiseEffects._();
  static final ProtonDenoiseEffects instance = ProtonDenoiseEffects._();

  final ProtonDenoiseChannel _channel = ProtonDenoiseChannel();

  /// Native plugin on iOS, macOS, Android, Linux, and Windows.
  static bool get isSupported => isProtonDenoisePlatformSupported;

  /// Same platforms as [isSupported] — WebRTC track attach pipeline.
  static bool get supportsWebRtcTrackPipeline =>
      isProtonDenoisePlatformSupported;

  Future<List<DenoiseTypeInfo>> listDenoiseTypes() =>
      _channel.listDenoiseTypes();

  Future<bool> isTypeReady(DenoiseType type) => _channel.isTypeReady(type);

  Future<void> attachDenoise({
    required String trackId,
    required DenoiseType type,
  }) => _channel.attach(trackId: trackId, type: type);

  Future<void> detachDenoise({required String trackId}) =>
      _channel.detach(trackId: trackId);
}

/// Low-level C API wrapper (desktop tests / frame processing without WebRTC attach).
///
/// On iOS/macOS/Android the legacy `proton_denoise` channel is not registered;
/// use [ProtonDenoiseEffects] for in-meeting mic denoise. Linux/Windows register both.
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
