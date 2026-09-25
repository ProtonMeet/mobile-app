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
    final SegmentationModelPreference?
    preference = switch (defaultTargetPlatform) {
      TargetPlatform.iOS ||
      TargetPlatform.macOS => SegmentationModelPreference.vision,
      // Square, not landscape: the engine turns the capture buffer upright before inference,
      // so what reaches the tensor is a portrait 9:16 frame. The landscape model's 256×144
      // input would squash that ~3× vertically and the mask comes back as a slab rather than
      // a silhouette. 256×256 costs a 1.8× squash instead.
      TargetPlatform.android => SegmentationModelPreference.single,
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

  /// Starts the desktop diagnostic frame tap on [trackId].
  ///
  /// Attaches a renderer to the local camera track and runs every frame through
  /// the segmentation engine, logging progress natively. The processed frames
  /// are not published — this exists to prove camera frames reach the engine on
  /// Windows and Linux. Returns false everywhere else.
  Future<bool> startFrameTap(String trackId) async {
    if (kIsWeb) {
      return false;
    }
    try {
      final started = await _channel.invokeMethod<bool>('startFrameTap', {
        'trackId': trackId,
      });
      return started ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('[ProtonVideoEffects] startFrameTap failed: $e');
      return false;
    }
  }

  /// Creates the desktop track that carries processed frames, returning its id.
  ///
  /// Null when the platform cannot provide one. The track is registered with
  /// flutter_webrtc, so the returned id resolves like any other track id and
  /// can be published in place of the camera track.
  Future<String?> createProcessedTrack() async {
    if (kIsWeb) {
      return null;
    }
    try {
      return await _channel.invokeMethod<String>('createProcessedTrack');
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('[ProtonVideoEffects] createProcessedTrack failed: $e');
      return null;
    }
  }

  /// Releases the track from [createProcessedTrack].
  Future<void> destroyProcessedTrack() async {
    if (kIsWeb) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('destroyProcessedTrack');
    } on MissingPluginException {
      return;
    } on PlatformException catch (e) {
      debugPrint('[ProtonVideoEffects] destroyProcessedTrack failed: $e');
    }
  }

  /// Stops the tap started by [startFrameTap]; logs the frame counts.
  Future<void> stopFrameTap(String trackId) async {
    if (kIsWeb) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('stopFrameTap', {'trackId': trackId});
    } on MissingPluginException {
      return;
    } on PlatformException catch (e) {
      debugPrint('[ProtonVideoEffects] stopFrameTap failed: $e');
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
