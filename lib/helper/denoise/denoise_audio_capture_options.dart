import 'package:livekit_client/livekit_client.dart';
import 'package:meet/managers/services/denoise_audio.service.dart';

/// LiveKit mic capture defaults when native denoise (DTLN / RNNoise / DeepFilter) is active.
///
/// Mirrors the web client: disable browser/WebRTC APM noise suppression so it does not
/// fight the post-capture denoiser (which can cause electrical / musical tail artifacts).
/// [stopAudioCaptureOnMute] keeps the MediaStreamTrack alive on mute so the denoise
/// processor is not torn down and re-created on every unmute.
AudioCaptureOptions resolveDenoiseAwareAudioCaptureOptions({
  String? deviceId,
  bool? echoCancellation,
  bool? autoGainControl,
}) {
  if (!DenoiseAudioService.instance.isAvailable) {
    return AudioCaptureOptions(
      deviceId: deviceId,
      echoCancellation: echoCancellation ?? true,
      autoGainControl: autoGainControl ?? true,
    );
  }
  return AudioCaptureOptions(
    deviceId: deviceId,
    noiseSuppression: false,
    voiceIsolation: false,
    stopAudioCaptureOnMute: false,
    echoCancellation: echoCancellation ?? true,
    autoGainControl: autoGainControl ?? true,
  );
}
