import 'package:flutter/foundation.dart'
    show debugPrint, defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter_webrtc/flutter_webrtc.dart';
// The umbrella exports no way to build a MediaStreamTrack from a track id,
// which is how the desktop processed track is handed back to LiveKit.
// ignore: implementation_imports
import 'package:flutter_webrtc/src/native/media_stream_track_impl.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:proton_video_effects/background_blur_config.dart';
import 'package:proton_video_effects/src/proton_video_effects_channel.dart';

/// LiveKit [TrackProcessor] that attaches native background blur on the camera track.
///
/// Create via [ProtonVideoEffects.createBlurTrackProcessor] — not directly.
///
/// On mobile and macOS [processedTrack] is null: native code edits frames in
/// place inside the WebRTC pipeline, so the published track never changes.
/// Windows and Linux have no such seam, so there the processor publishes a
/// second track carrying the composited frames — see [_isDesktop].
class BackgroundBlurTrackProcessor
    extends TrackProcessor<VideoProcessorOptions> {
  BackgroundBlurTrackProcessor({
    required ProtonVideoEffectsChannel channel,
    BackgroundBlurConfig? config,
    bool effectActive = true,
  }) : _channel = channel,
       _config = config,
       _effectActive = effectActive;

  final ProtonVideoEffectsChannel _channel;
  BackgroundBlurConfig? _config;

  /// Whether an effect was selected when the track was created.
  ///
  /// A "none" selection produces the same [BackgroundBlurConfig] as blur, so
  /// intent cannot be read back from [_config]. Desktop installs the processor
  /// even for "none" — see [_isDesktop] — and relies on this to leave the
  /// engine detached so frames pass through.
  final bool _effectActive;

  void setBackgroundBlurConfig(BackgroundBlurConfig config) {
    _config = config;
  }

  String? _attachedTrackId;
  String? _tappedTrackId;
  MediaStreamTrack? _processedTrack;

  /// Platforms where blur needs a separate published track rather than
  /// in-place frame editing.
  static bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  @override
  String get name => 'proton_background_blur';

  @override
  MediaStreamTrack? get processedTrack => _processedTrack;

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
      // Desktop needs the pipeline up before any effect is chosen, because the
      // track it publishes cannot be swapped in later. Attaching is what turns
      // the effect on, so a "none" selection deliberately skips it and lets
      // frames pass through.
      if (_effectActive) {
        await _channel.attachBackgroundBlur(trackId: trackId, config: config);
        _attachedTrackId = trackId;
        debugPrint(
          '[ProtonVideoEffects] Attached background blur for track $trackId',
        );
      }
      if (_isDesktop) {
        await _startDesktopPipeline(trackId);
      } else if (!_effectActive) {
        debugPrint(
          '[ProtonVideoEffects] No effect selected; camera left unchanged.',
        );
      }
    } catch (e, st) {
      debugPrint('[ProtonVideoEffects] attach failed: $e\n$st');
    }
  }

  /// Routes composited frames from [cameraTrackId] onto a second, published
  /// track.
  ///
  /// The destination is created first so no processed frame is produced before
  /// there is somewhere to put it. Leaving [_processedTrack] null on failure is
  /// what makes this degrade to an unblurred camera rather than a black one.
  Future<void> _startDesktopPipeline(String cameraTrackId) async {
    final processedId = await _channel.createProcessedTrack();
    if (processedId == null || processedId.isEmpty) {
      debugPrint(
        '[ProtonVideoEffects] No processed track; publishing camera unchanged.',
      );
      return;
    }
    final tapping = await _channel.startFrameTap(cameraTrackId);
    if (!tapping) {
      debugPrint(
        '[ProtonVideoEffects] Frame tap refused $cameraTrackId; '
        'dropping processed track $processedId.',
      );
      await _channel.destroyProcessedTrack();
      return;
    }
    _tappedTrackId = cameraTrackId;
    // Registered in flutter_webrtc's local track map by createProcessedTrack,
    // so this id resolves for every later channel call.
    _processedTrack = MediaStreamTrackNative(
      processedId,
      'proton-video-effects',
      'video',
      true,
      '',
    );
    debugPrint(
      '[ProtonVideoEffects] Publishing processed track $processedId '
      'fed by camera $cameraTrackId',
    );
  }

  @override
  Future<void> restart(VideoProcessorOptions options) async {
    await destroy();
    await init(options);
  }

  @override
  Future<void> destroy() async {
    final id = _attachedTrackId;
    final tapped = _tappedTrackId;
    _attachedTrackId = null;
    _tappedTrackId = null;
    // Cleared before the awaits so a concurrent publish cannot pick up a track
    // that is being torn down.
    final hadProcessedTrack = _processedTrack != null;
    _processedTrack = null;

    if (tapped != null) {
      try {
        await _channel.stopFrameTap(tapped);
      } catch (e, st) {
        debugPrint('[ProtonVideoEffects] stopFrameTap failed: $e\n$st');
      }
    }
    if (hadProcessedTrack) {
      try {
        await _channel.destroyProcessedTrack();
      } catch (e, st) {
        debugPrint(
          '[ProtonVideoEffects] destroyProcessedTrack failed: $e\n$st',
        );
      }
    }
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
