/// On-device camera video effects for Proton Meet.
///
/// Import this library only:
/// `import 'package:proton_video_effects/proton_video_effects.dart';`
///
/// Native I/O is routed through [ProtonVideoEffects]. Implementation details
/// live under `lib/src/` and are not part of the public API.
library;

export 'background_blur_config.dart';
export 'background_blur_track_processor.dart';
export 'camera_background_mode.dart';
export 'mask_edge_tuning.dart';
export 'segmentation_model_debug_info.dart';
export 'segmentation_model_preference.dart';

import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'background_blur_config.dart';
import 'background_blur_track_processor.dart';
import 'segmentation_model_debug_info.dart';
import 'segmentation_model_preference.dart';
import 'src/proton_video_effects_channel.dart';

/// Entry point for camera background blur and future video effects.
///
/// Use [instance] for all native calls. Typical Meet integration:
///
/// ```dart
/// if (!ProtonVideoEffects.isSupported) return;
///
/// // Preferred — blur attaches when the LiveKit camera track starts
/// final processor = ProtonVideoEffects.instance.createBlurTrackProcessor(
///   config: const BackgroundBlurConfig(),
/// );
///
/// // Or attach / detach on an existing WebRTC track id
/// await ProtonVideoEffects.instance.attachBackgroundBlur(trackId: id);
/// await ProtonVideoEffects.instance.detachBackgroundBlur(trackId: id);
/// ```
///
/// Segmentation defaults (Vision on Apple, landscape MediaPipe on Android) are
/// applied once before the first attach via [applyPlatformDefaultSegmentationModel].
class ProtonVideoEffects {
  ProtonVideoEffects._();

  /// Shared facade for the app process.
  static final ProtonVideoEffects instance = ProtonVideoEffects._();

  final ProtonVideoEffectsChannel _channel = ProtonVideoEffectsChannel();

  /// `true` on iOS, Android, macOS, Linux, and Windows; `false` on web.
  static bool get isSupported => !kIsWeb;

  /// LiveKit [BackgroundBlurTrackProcessor] sharing this facade's channel client.
  ///
  /// Pass the result to `LocalVideoTrack.createCameraTrack`. Do not construct
  /// [BackgroundBlurTrackProcessor] yourself — it must share this facade's channel.
  /// Set [effectActive] to false to install the processor without turning an
  /// effect on. Only useful on Windows and Linux, where the processor publishes
  /// its own track and so must exist from the moment the track is created.
  BackgroundBlurTrackProcessor createBlurTrackProcessor({
    BackgroundBlurConfig? config,
    bool effectActive = true,
  }) {
    return BackgroundBlurTrackProcessor(
      channel: _channel,
      config: config,
      effectActive: effectActive,
    );
  }

  /// Whether the native blur pipeline and models are loaded on this device.
  Future<bool> isBackgroundBlurReady() => _channel.isBackgroundBlurReady();

  /// Pushes blur tuning (σ, obscure opacity) to native without re-attaching.
  Future<void> setBackgroundBlurConfig(BackgroundBlurConfig config) =>
      _channel.setBackgroundBlurConfig(config);

  /// Attaches blur processing to an existing local camera [trackId].
  ///
  /// Prefer [createBlurTrackProcessor] when creating a new track. Use this when
  /// toggling blur on a track that is already capturing.
  Future<void> attachBackgroundBlur({
    required String trackId,
    BackgroundBlurConfig? config,
  }) => _channel.attachBackgroundBlur(trackId: trackId, config: config);

  /// Stops blur on [trackId]; the camera track keeps running unblurred.
  Future<void> detachBackgroundBlur({required String trackId}) =>
      _channel.detachBackgroundBlur(trackId: trackId);

  /// Still-image virtual background from a local file (not enabled in production).
  Future<void> setReplacementBackgroundImagePath(String filePath) =>
      _channel.setReplacementBackgroundImage(filePath: filePath);

  /// Still-image virtual background from JPEG/PNG bytes (not enabled in production).
  Future<void> setReplacementBackgroundImageBytes(Uint8List bytes) =>
      _channel.setReplacementBackgroundImage(imageBytes: bytes);

  /// Clears a replacement background and returns to blur mode (not enabled in production).
  Future<void> clearReplacementBackground() =>
      _channel.clearReplacementBackground();

  /// Sets the platform segmentation backend once per process (before first attach).
  ///
  /// iOS / macOS → [SegmentationModelPreference.vision];
  /// Android → [SegmentationModelPreference.single].
  Future<void> applyPlatformDefaultSegmentationModel() =>
      _channel.applyPlatformDefaultSegmentationModel();

  /// Overrides the segmentation model (debug / QA tuning).
  Future<void> setSegmentationModelPreference(
    SegmentationModelPreference preference,
  ) => _channel.setSegmentationModelPreference(preference);

  /// Reads back which segmenter and backend native is using (debug UI).
  Future<SegmentationModelDebugInfo> getSegmentationModelInfo() =>
      _channel.getSegmentationModelInfo();

  /// Runs the desktop camera frames through the engine without publishing them.
  ///
  /// Diagnostic only, for Windows and Linux: it proves frames reach the
  /// segmenter while the publish path is still missing. Progress is logged
  /// natively under the `ProtonVideoEffects` tag.
  Future<bool> startFrameTap(String trackId) => _channel.startFrameTap(trackId);

  /// Stops [startFrameTap] and logs how many frames were processed.
  Future<void> stopFrameTap(String trackId) => _channel.stopFrameTap(trackId);

  /// Creates the desktop track fed by the processed frames, returning its id.
  ///
  /// Windows and Linux only; null elsewhere and on failure. Publish this track
  /// in place of the camera track to make the effect visible to remote peers.
  Future<String?> createProcessedTrack() => _channel.createProcessedTrack();

  /// Releases the track from [createProcessedTrack].
  Future<void> destroyProcessedTrack() => _channel.destroyProcessedTrack();
}
