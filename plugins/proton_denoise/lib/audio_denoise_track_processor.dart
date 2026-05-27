import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:livekit_client/livekit_client.dart';

import 'proton_denoise_channel.dart';
import 'src/denoise_platform.dart';
import 'src/denoise_type.dart';

/// LiveKit [TrackProcessor] that attaches native mic denoise on the local audio track.
///
/// [processedTrack] stays null: processing runs in the flutter_webrtc capture pipeline.
class AudioDenoiseTrackProcessor extends TrackProcessor<AudioProcessorOptions> {
  AudioDenoiseTrackProcessor({
    required this.type,
    ProtonDenoiseChannel? channel,
  }) : _channel = channel ?? ProtonDenoiseChannel();

  final DenoiseType type;
  final ProtonDenoiseChannel _channel;

  String? _attachedTrackId;

  @override
  String get name => 'proton_audio_denoise_${type.id}';

  @override
  MediaStreamTrack? get processedTrack => null;

  @override
  Future<void> init(AudioProcessorOptions options) async {
    await destroy();
    if (!isProtonDenoisePlatformSupported || type == DenoiseType.none) {
      return;
    }
    final ready = await _channel.isTypeReady(type);
    if (!ready) {
      debugPrint(
        '[ProtonDenoise] ${type.displayName} not ready; mic unchanged.',
      );
      return;
    }
    final trackId = options.track.id;
    if (trackId == null || trackId.isEmpty) {
      debugPrint('[ProtonDenoise] Missing track id; skip attach.');
      return;
    }
    try {
      await _channel.attach(trackId: trackId, type: type);
      _attachedTrackId = trackId;
      debugPrint('[ProtonDenoise] Attached ${type.id} for track $trackId');
    } catch (e, st) {
      debugPrint('[ProtonDenoise] attach failed: $e\n$st');
    }
  }

  @override
  Future<void> restart(AudioProcessorOptions options) async {
    await destroy();
    await init(options);
  }

  @override
  Future<void> destroy() async {
    final id = _attachedTrackId;
    _attachedTrackId = null;
    if (id != null) {
      try {
        await _channel.detach(trackId: id);
      } catch (e, st) {
        debugPrint('[ProtonDenoise] detach failed: $e\n$st');
      }
    }
  }

  @override
  Future<void> onPublish(Room room) async {}

  @override
  Future<void> onUnpublish() async {}
}
