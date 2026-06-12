import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:proton_video_effects/background_blur_config.dart';
import 'package:proton_video_effects/src/proton_video_effects_channel.dart';

/// LiveKit [TrackProcessor] that attaches native background blur on the camera track.
///
/// Create via [ProtonVideoEffects.createBlurTrackProcessor] — not directly.
///
/// [processedTrack] is always null: native code processes frames in the WebRTC pipeline.
class BackgroundBlurTrackProcessor
    extends TrackProcessor<VideoProcessorOptions> {
  BackgroundBlurTrackProcessor({
    required ProtonVideoEffectsChannel channel,
    BackgroundBlurConfig? config,
  }) : _channel = channel,
       _config = config;

  final ProtonVideoEffectsChannel _channel;
  BackgroundBlurConfig? _config;

  void setBackgroundBlurConfig(BackgroundBlurConfig config) {
    _config = config;
  }

  String? _attachedTrackId;

  @override
  String get name => 'proton_background_blur';

  @override
  MediaStreamTrack? get processedTrack => null;

  @override
  Future<void> init(VideoProcessorOptions options) async {
    await destroy();
    final ready = await _channel.isBackgroundBlurReady();
    if (!ready) {
      debugPrint(
        '[ProtonVideoEffects] Background blur not ready; camera unchanged.',
      );
      return;
    }
    final trackId = options.track.id;
    if (trackId == null || trackId.isEmpty) {
      debugPrint('[ProtonVideoEffects] Missing track id; skip attach.');
      return;
    }
    try {
      final config = _config;
      if (config != null) {
        await _channel.setBackgroundBlurConfig(config);
      }
      await _channel.attachBackgroundBlur(trackId: trackId, config: config);
      _attachedTrackId = trackId;
      debugPrint(
        '[ProtonVideoEffects] Attached background blur for track $trackId',
      );
    } catch (e, st) {
      debugPrint('[ProtonVideoEffects] attach failed: $e\n$st');
    }
  }

  @override
  Future<void> restart(VideoProcessorOptions options) async {
    await destroy();
    await init(options);
  }

  @override
  Future<void> destroy() async {
    final id = _attachedTrackId;
    _attachedTrackId = null;
    if (id != null) {
      try {
        await _channel.detachBackgroundBlur(trackId: id);
      } catch (e, st) {
        debugPrint('[ProtonVideoEffects] detach failed: $e\n$st');
      }
    }
  }

  @override
  Future<void> onPublish(Room room) async {}

  @override
  Future<void> onUnpublish() async {}
}
