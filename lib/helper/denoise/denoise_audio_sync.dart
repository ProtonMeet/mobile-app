import 'package:livekit_client/livekit_client.dart';
import 'package:meet/helper/denoise/denoise_audio_lifecycle.dart';
import 'package:proton_denoise/proton_denoise.dart';

export 'denoise_audio_capture_options.dart';
export 'denoise_audio_lifecycle.dart';

/// Attaches or detaches native mic denoise for the local audio track.
Future<void> syncLocalAudioDenoise({
  required Room room,
  required bool enabled,
  DenoiseType type = DenoiseType.rnnoise,
  DenoiseAttachReason reason = DenoiseAttachReason.settings,
}) {
  return DenoiseAudioLifecycle.instance.sync(
    room: room,
    enabled: enabled,
    type: type,
    reason: reason,
  );
}

/// Re-attach denoise after mic toggle or device change when the track may have been replaced.
Future<void> syncLocalAudioDenoiseIfNeeded({
  required Room room,
  required bool enabled,
  required DenoiseType type,
  DenoiseAttachReason reason = DenoiseAttachReason.toggle,
}) {
  return DenoiseAudioLifecycle.instance.syncIfNeeded(
    room: room,
    enabled: enabled,
    type: type,
    reason: reason,
  );
}
