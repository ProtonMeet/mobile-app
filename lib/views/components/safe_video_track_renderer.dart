import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/helper/logger.dart' as l;

/// Wrapper widget for VideoTrackRenderer that disables tap-to-focus.
/// Try to avoid sentry error: "PlatformException(error,
/// Attempt to invoke virtual method 'int io.flutter.embedding.engine.systemchannels.PlatformChannel$DeviceOrientation.ordinal()'
/// on a null object reference, null"
///
/// When a local track's processor publishes a separate processed track
/// (background effects on Windows/Linux), that track is rendered instead:
/// LiveKit only swaps the published track, and its renderer keeps showing the
/// raw camera stream.
class SafeVideoTrackRenderer extends StatefulWidget {
  final VideoTrack videoTrack;
  final VideoViewFit fit;
  final VideoRenderMode renderMode;
  final VideoViewMirrorMode mirrorMode;

  const SafeVideoTrackRenderer({
    required this.videoTrack,
    this.fit = VideoViewFit.cover,
    this.renderMode = VideoRenderMode.platformView,
    this.mirrorMode = VideoViewMirrorMode.auto,
    super.key,
  });

  @override
  State<SafeVideoTrackRenderer> createState() => _SafeVideoTrackRendererState();
}

class _SafeVideoTrackRendererState extends State<SafeVideoTrackRenderer> {
  EventsListener<TrackEvent>? _listener;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(covariant SafeVideoTrackRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoTrack != widget.videoTrack) {
      _listen();
    }
  }

  @override
  void dispose() {
    unawaited(_listener?.dispose());
    super.dispose();
  }

  void _listen() {
    unawaited(_listener?.dispose());
    _listener = widget.videoTrack.createListener()
      ..on<TrackProcessorUpdateEvent>((_) {
        if (mounted) setState(() {});
      });
  }

  rtc.MediaStreamTrack? get _processedTrack {
    if (kIsWeb) return null;
    final track = widget.videoTrack;
    if (track is! LocalVideoTrack) return null;
    return track.processor?.processedTrack;
  }

  bool _mirrorProcessed() {
    switch (widget.mirrorMode) {
      case VideoViewMirrorMode.mirror:
        return true;
      case VideoViewMirrorMode.off:
        return false;
      case VideoViewMirrorMode.auto:
        final options = (widget.videoTrack as LocalVideoTrack).currentOptions;
        return options is CameraCaptureOptions &&
            options.cameraPosition == CameraPosition.front;
    }
  }

  @override
  Widget build(BuildContext context) {
    final processed = _processedTrack;
    return IgnorePointer(
      // ignore: avoid_redundant_argument_values
      ignoring: true,
      child: processed != null
          ? _ProcessedTrackView(
              key: ValueKey(processed.id),
              track: processed,
              fit: widget.fit == VideoViewFit.cover
                  ? rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover
                  : rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
              mirror: _mirrorProcessed(),
            )
          : VideoTrackRenderer(
              fit: widget.fit,
              renderMode: widget.renderMode,
              mirrorMode: widget.mirrorMode,
              widget.videoTrack,
            ),
    );
  }
}

/// Renders a single local track through its own preview stream.
class _ProcessedTrackView extends StatefulWidget {
  const _ProcessedTrackView({
    required this.track,
    required this.fit,
    required this.mirror,
    super.key,
  });

  final rtc.MediaStreamTrack track;
  final rtc.RTCVideoViewObjectFit fit;
  final bool mirror;

  @override
  State<_ProcessedTrackView> createState() => _ProcessedTrackViewState();
}

class _ProcessedTrackViewState extends State<_ProcessedTrackView> {
  final _renderer = rtc.RTCVideoRenderer();
  rtc.MediaStream? _stream;
  bool _ready = false;
  late final Future<void> _opening;

  @override
  void initState() {
    super.initState();
    _opening = _open();
  }

  @override
  void dispose() {
    unawaited(_opening.whenComplete(_release));
    super.dispose();
  }

  Future<void> _open() async {
    try {
      await _renderer.initialize();
      final stream = await rtc.createLocalMediaStream('proton-fx-preview');
      _stream = stream;
      await stream.addTrack(widget.track);
      if (!mounted) return;
      _renderer.srcObject = stream;
      setState(() => _ready = true);
    } catch (e) {
      l.logger.e('[SafeVideoTrackRenderer] processed preview failed: $e');
    }
  }

  Future<void> _release() async {
    final stream = _stream;
    _stream = null;
    if (stream != null) {
      // Disposing a native stream unregisters every track it still holds, and
      // the processed track is owned by the publisher, so detach it first.
      try {
        await stream.removeTrack(widget.track);
      } catch (_) {}
      try {
        await stream.dispose();
      } catch (_) {}
    }
    try {
      await _renderer.dispose();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.shrink();
    return rtc.RTCVideoView(
      _renderer,
      mirror: widget.mirror,
      objectFit: widget.fit,
      filterQuality: FilterQuality.high,
    );
  }
}
