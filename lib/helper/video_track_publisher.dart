import 'package:livekit_client/livekit_client.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/views/scenes/prejoin/prejoin_state.dart';

/// Publishes a video track with preferred codec, falling back to VP8 if it fails.
///
/// This function tries to publish the video track with the preferred codec first.
/// If that fails, it will:
/// 1. Stop and dispose the failed track
/// 2. Create a new track using the provided [createTrack] function
/// 3. Publish with VP8 codec
///
/// Parameters:
/// - [participant]: The local participant to publish the track to
/// - [initialTrack]: The initial video track to publish (will be disposed if first attempt fails)
/// - [createTrack]: Function to create a new video track (called if fallback is needed)
/// - [publishOptions]: The video publish options (should include preferred codec)
///
/// Returns: The successfully published video track (either the original or recreated one)
///
/// Throws: Exception if both attempts fail
Future<LocalVideoTrack> publishVideoTrackWithFallback({
  required LocalParticipant participant,
  required LocalVideoTrack initialTrack,
  required Future<LocalVideoTrack> Function() createTrack,
  required VideoPublishOptions publishOptions,
}) async {
  LocalVideoTrack currentTrack = initialTrack;
  final preferredCodec = publishOptions.videoCodec;

  try {
    // Try to publish with preferred codec
    await participant.publishVideoTrack(
      currentTrack,
      publishOptions: publishOptions,
    );
    l.logger.i(
      '[VideoTrack] Successfully published video track with $preferredCodec codec',
    );
    return currentTrack;
  } catch (e) {
    l.logger.e(
      '[VideoTrack] Failed to publish video track with $preferredCodec codec: $e',
    );

    // Only fallback if we're not already using VP8
    if (preferredCodec.toLowerCase() == VideoCodec.vp8.lowerCase) {
      l.logger.e('[VideoTrack] Already using VP8, cannot fallback further');
      rethrow;
    }

    l.logger.i('[VideoTrack] Fallback to vp8 codec');

    // Dispose the failed track and recreate a new one
    try {
      await currentTrack.stop();
      await currentTrack.dispose();
    } catch (disposeError) {
      l.logger.e('[VideoTrack] Error disposing failed track: $disposeError');
    }

    // Recreate the camera track using provided function
    currentTrack = await createTrack();

    // Fallback to publish with vp8 codec
    await participant.publishVideoTrack(
      currentTrack,
      publishOptions: publishOptions.copyWith(
        videoCodec: VideoCodec.vp8.toString(),
      ),
    );

    l.logger.i(
      '[VideoTrack] Successfully published video track with vp8 codec',
    );
    return currentTrack;
  }
}
