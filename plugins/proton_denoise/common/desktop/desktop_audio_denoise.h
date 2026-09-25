/*
 * Copyright (c) 2026 Proton AG
 * Desktop (Linux/Windows) backend for `me.proton.meet/denoise` and RNNoise C API.
 */

#ifndef PROTON_DESKTOP_AUDIO_DENOISE_H_
#define PROTON_DESKTOP_AUDIO_DENOISE_H_

#include <string>
#include <vector>

namespace proton_denoise {

struct DesktopMethodResult {
  bool success = true;
  bool bool_value = false;
  int int_value = 0;
  float float_value = 0.f;
  std::string error_code;
  std::string error_message;
};

/// One entry of `listDenoiseTypes` / `diagnoseDenoise`.
///
/// Ids must match `DenoiseType.id` in `lib/denoise_type.dart`.
struct DenoiseTypeEntry {
  std::string id;
  std::string display_name;
  bool is_ready = false;
  /// Why a backend is unavailable; surfaced as `details.status` for debug UI.
  std::string status;
};

/// Result of `warmUpDenoise` for a single backend.
struct DenoiseWarmUpEntry {
  std::string id;
  bool warm_up_ok = false;
  int warm_up_ms = 0;
  std::string status;
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

  /// Backends exposed to Dart, in settings-UI order. RNNoise is the only one
  /// implemented on desktop; the others report why they are unavailable.
  std::vector<DenoiseTypeEntry> ListDenoiseTypes() const;

  /// Production-style init probe. Empty [type_id] warms every backend.
  std::vector<DenoiseWarmUpEntry> WarmUp(const std::string& type_id);

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
