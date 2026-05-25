import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:livekit_client/livekit_client.dart';

import 'proton_video_effects_channel.dart';

/// TODO:: this seems unnesscery must have. we can dirrectly use ProtonVideoEffects
/// LiveKit [TrackProcessor] that attaches native background blur on the camera track.
///
/// [processedTrack] is always null: the encoder keeps the same source track while native
/// code processes frames in the flutter_webrtc capturer pipeline.
class BackgroundBlurTrackProcessor
    extends TrackProcessor<VideoProcessorOptions> {
  BackgroundBlurTrackProcessor({ProtonVideoEffectsChannel? channel})
    : _channel = channel ?? ProtonVideoEffectsChannel();

  ProtonVideoEffectsChannel _channel;

  /// For tests: inject a mock channel.
  void debugOverrideChannel(ProtonVideoEffectsChannel channel) {
    _channel = channel;
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
      await _channel.attachBackgroundBlur(trackId: trackId);
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
  Future<void> onPublish(Room room) async {
    ///
  }

  @override
  Future<void> onUnpublish() async {
    ///
  }
}
