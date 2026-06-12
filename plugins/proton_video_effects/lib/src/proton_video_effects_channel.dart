import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';
import 'package:meta/meta.dart';
import 'package:proton_video_effects/background_blur_config.dart';
import 'package:proton_video_effects/segmentation_model_debug_info.dart';
import 'package:proton_video_effects/segmentation_model_preference.dart';

/// Channel name for the native plugin.
@internal
const String kProtonVideoEffectsChannelName = 'me.proton.meet/video_effects';

/// Which effect to apply on the local camera track. Only [backgroundBlur] is implemented.
enum VideoEffectKind {
  backgroundBlur,

  /// Roadmap: image/video virtual background.
  customBackground,
}

/// Internal method-channel client; use [ProtonVideoEffects] from app code.
@internal
class ProtonVideoEffectsChannel {
  ProtonVideoEffectsChannel()
    : _channel = const MethodChannel(kProtonVideoEffectsChannelName);

  final MethodChannel _channel;
  bool _platformSegmentationDefaultsApplied = false;

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

  Future<void> setBackgroundBlurConfig(BackgroundBlurConfig config) async {
    if (kIsWeb) {
      return;
    }
    try {
      await _channel.invokeMethod<void>(
        'setBackgroundBlurConfig',
        config.toMethodChannelArgs(),
      );
    } on MissingPluginException {
      return;
    } on PlatformException catch (e) {
      debugPrint('[ProtonVideoEffects] setBackgroundBlurConfig failed: $e');
      rethrow;
    }
  }

  Future<void> applyPlatformDefaultSegmentationModel() async {
    if (kIsWeb || _platformSegmentationDefaultsApplied) {
      return;
    }
    final SegmentationModelPreference? preference =
        switch (defaultTargetPlatform) {
          TargetPlatform.iOS ||
          TargetPlatform.macOS => SegmentationModelPreference.vision,
          TargetPlatform.android => SegmentationModelPreference.landscape,
          _ => null,
        };
    if (preference == null) {
      return;
    }
    _platformSegmentationDefaultsApplied = true;
    await setSegmentationModelPreference(preference);
  }

  Future<void> attachBackgroundBlur({
    required String trackId,
    BackgroundBlurConfig? config,
  }) async {
    await applyPlatformDefaultSegmentationModel();
    await _invokeAttachDetach('attach', trackId, config: config);
  }

  Future<void> detachBackgroundBlur({required String trackId}) async {
    await _invokeAttachDetach('detach', trackId);
  }

  Future<void> setReplacementBackgroundImage({
    String? filePath,
    Uint8List? imageBytes,
  }) async {
    if (kIsWeb || !BackgroundBlurConfig.replacementBackgroundEnabled) {
      return;
    }
    if ((filePath == null || filePath.isEmpty) &&
        (imageBytes == null || imageBytes.isEmpty)) {
      throw ArgumentError(
        'filePath or imageBytes required for setReplacementBackgroundImage',
      );
    }
    try {
      final args = <String, dynamic>{
        if (filePath != null && filePath.isNotEmpty) 'filePath': filePath,
        if (imageBytes != null && imageBytes.isNotEmpty)
          'imageBytes': imageBytes,
      };
      await _channel.invokeMethod<void>('setReplacementBackgroundImage', args);
    } on MissingPluginException {
      return;
    } on PlatformException catch (e) {
      debugPrint(
        '[ProtonVideoEffects] setReplacementBackgroundImage failed: $e',
      );
      rethrow;
    }
  }

  Future<void> setSegmentationModelPreference(
    SegmentationModelPreference preference,
  ) async {
    if (kIsWeb) {
      return;
    }
    final model = preference.channelId;
    try {
      await _channel.invokeMethod<void>('setSegmentationModel', {
        'model': model,
      });
    } on MissingPluginException {
      return;
    } on PlatformException catch (e) {
      debugPrint('[ProtonVideoEffects] setSegmentationModel failed: $e');
      rethrow;
    }
  }

  Future<SegmentationModelDebugInfo> getSegmentationModelInfo() async {
    if (kIsWeb) {
      return const SegmentationModelDebugInfo(
        model: null,
        backend: 'web',
        forced: false,
        supported: false,
      );
    }
    try {
      final map = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getSegmentationModel',
      );
      return SegmentationModelDebugInfo.fromMap(map);
    } on MissingPluginException {
      return const SegmentationModelDebugInfo(
        model: null,
        backend: 'unknown',
        forced: false,
        supported: false,
      );
    } on PlatformException {
      return const SegmentationModelDebugInfo(
        model: null,
        backend: 'unknown',
        forced: false,
        supported: false,
      );
    }
  }

  Future<void> clearReplacementBackground() async {
    if (kIsWeb || !BackgroundBlurConfig.replacementBackgroundEnabled) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('clearReplacementBackground');
    } on MissingPluginException {
      return;
    } on PlatformException catch (e) {
      debugPrint('[ProtonVideoEffects] clearReplacementBackground failed: $e');
      rethrow;
    }
  }

  Future<void> _invokeAttachDetach(
    String method,
    String trackId, {
    BackgroundBlurConfig? config,
  }) async {
    if (kIsWeb) {
      return;
    }
    try {
      final args = <String, dynamic>{'trackId': trackId};
      if (config != null) {
        args.addAll(config.toMethodChannelArgs());
      }
      await _channel.invokeMethod<void>(method, args);
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
