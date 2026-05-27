/*
 * Copyright (c) 2026 Proton AG
 * Desktop (Linux/Windows) backend for `me.proton.meet/denoise` and RNNoise C API.
 */

#ifndef PROTON_DESKTOP_AUDIO_DENOISE_H_
#define PROTON_DESKTOP_AUDIO_DENOISE_H_

#include <string>

namespace proton_denoise {

struct DesktopMethodResult {
  bool success = true;
  bool bool_value = false;
  int int_value = 0;
  float float_value = 0.f;
  std::string error_code;
  std::string error_message;
  /// JSON-like payload for listDenoiseTypes; empty when not used.
  std::string json_list_payload;
};

class DesktopAudioDenoise {
 public:
  static DesktopAudioDenoise& Instance();

  DesktopMethodResult Handle(const std::string& channel,
                             const std::string& method,
                             const std::string& track_id,
                             const std::string& type_id,
                             bool enabled_flag);

  bool IsRnnoiseReady() const;

  /// Legacy `proton_denoise` channel: in-place frame processing (tests / tools).
  DesktopMethodResult ProcessFrame(float* samples,
                                   size_t sample_count,
                                   int channels);

 private:
  DesktopAudioDenoise() = default;

  DesktopMethodResult HandleEffectsChannel(const std::string& method,
                                           const std::string& track_id,
                                           const std::string& type_id);
  DesktopMethodResult HandleLegacyChannel(const std::string& method,
                                          bool enabled_flag);
  bool WebRtcAvailable() const;
  void EnsureRnnoiseHandle();
  void DestroyRnnoiseHandle();
};

}  // namespace proton_denoise

#endif  // PROTON_DESKTOP_AUDIO_DENOISE_H_
