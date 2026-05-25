/// On-device camera video effects (background blur; custom backgrounds planned).
library;

export 'background_blur_track_processor.dart';
export 'proton_video_effects_channel.dart';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'proton_video_effects_channel.dart';

/// Facade for attaching effects to flutter_webrtc local camera tracks.
class ProtonVideoEffects {
  ProtonVideoEffects._();
  static final ProtonVideoEffects instance = ProtonVideoEffects._();

  final ProtonVideoEffectsChannel _channel = ProtonVideoEffectsChannel();

  static bool get isSupported => !kIsWeb;

  Future<bool> isBackgroundBlurReady() => _channel.isBackgroundBlurReady();

  Future<void> attachBackgroundBlur({required String trackId}) =>
      _channel.attachBackgroundBlur(trackId: trackId);

  Future<void> detachBackgroundBlur({required String trackId}) =>
      _channel.detachBackgroundBlur(trackId: trackId);
}
