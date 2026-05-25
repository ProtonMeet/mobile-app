import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart';

/// Method channel for native camera video effects (blur today; custom backgrounds later).
const String kProtonVideoEffectsChannelName = 'me.proton.meet/video_effects';

/// Which effect to apply on the local camera track. Only [backgroundBlur] is implemented.
enum VideoEffectKind {
  backgroundBlur,

  /// Roadmap: image/video virtual background.
  customBackground,
}

class ProtonVideoEffectsChannel {
  ProtonVideoEffectsChannel()
    : _channel = const MethodChannel(kProtonVideoEffectsChannelName);

  final MethodChannel _channel;

  /// Whether [VideoEffectKind.backgroundBlur] is available on this platform.
  Future<bool> isBackgroundBlurReady() async {
    if (kIsWeb) {
      return false;
    }
    try {
      final ready = await _channel.invokeMethod<bool>('isImplementationReady');
      return ready ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> attachBackgroundBlur({required String trackId}) async {
    await _invokeAttachDetach('attach', trackId);
  }

  Future<void> detachBackgroundBlur({required String trackId}) async {
    await _invokeAttachDetach('detach', trackId);
  }

  Future<void> _invokeAttachDetach(String method, String trackId) async {
    if (kIsWeb) {
      return;
    }
    try {
      await _channel.invokeMethod<void>(method, <String, dynamic>{
        'trackId': trackId,
      });
    } on MissingPluginException {
      return;
    } on PlatformException catch (e) {
      if (e.code == 'WEBRTC_NOT_READY') {
        return;
      }
      debugPrint('[ProtonVideoEffects] $method failed: $e');
      rethrow;
    }
  }
}
