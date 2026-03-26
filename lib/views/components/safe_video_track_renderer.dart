import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

/// Wrapper widget for VideoTrackRenderer that disables tap-to-focus.
/// Try to avoid sentry error: "PlatformException(error,
/// Attempt to invoke virtual method 'int io.flutter.embedding.engine.systemchannels.PlatformChannel$DeviceOrientation.ordinal()'
/// on a null object reference, null"
class SafeVideoTrackRenderer extends StatelessWidget {
  final VideoTrack videoTrack;
  final VideoViewFit fit;
  final VideoRenderMode renderMode;
  final VideoViewMirrorMode mirrorMode;

  const SafeVideoTrackRenderer({
    required this.videoTrack,
    this.fit = VideoViewFit.cover,
    this.renderMode = VideoRenderMode.auto,
    this.mirrorMode = VideoViewMirrorMode.auto,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      // ignore: avoid_redundant_argument_values
      ignoring: true,
      child: VideoTrackRenderer(
        fit: fit,
        renderMode: renderMode,
        mirrorMode: mirrorMode,
        videoTrack,
      ),
    );
  }
}
