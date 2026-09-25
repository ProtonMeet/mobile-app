/*
 * Copyright (c) 2026 Proton AG
 * Desktop (Linux/Windows) method-channel backend for background blur.
 */

#ifndef MEET_DESKTOP_BACKGROUND_BLUR_H_
#define MEET_DESKTOP_BACKGROUND_BLUR_H_

#include <cstdint>
#include <string>
#include <vector>

#include "desktop_image_decoder.h"

namespace meet_video_effects {

/**
 * A channel reply, self-describing so the platform plugins do not have to know
 * which methods return values.
 *
 * Keying that off method names silently turned `startFrameTap`'s answer into
 * null once a second bool-returning method appeared, so use [SetBool] /
 * [SetString] rather than assigning the fields directly.
 */
struct DesktopMethodResult {
  bool success = true;
  bool bool_value = false;
  /** Whether [bool_value] should be sent; false means reply with null. */
  bool has_bool_value = false;
  std::string string_value;
  bool has_string_value = false;
  std::string error_code;
  std::string error_message;

  void SetBool(bool value) {
    bool_value = value;
    has_bool_value = true;
  }

  void SetString(std::string value) {
    string_value = std::move(value);
    has_string_value = true;
  }
};

/**
 * One processed frame, in I420 (libwebrtc plane layout).
 *
 * The planes point into buffers the engine reuses, so they are only valid until
 * the next [DesktopBackgroundBlur::ProcessI420] call: copy before returning to
 * the capture thread.
 */
struct ProcessedI420 {
  const uint8_t* y = nullptr;
  const uint8_t* u = nullptr;
  const uint8_t* v = nullptr;
  int stride_y = 0;
  int stride_u = 0;
  int stride_v = 0;
  int width = 0;
  int height = 0;
};

/**
 * Mask shaping dials, mirroring Dart's `MaskEdgeTuning`.
 *
 * Defaults match that class so a client that never sends the `mask*` keys — an
 * older build, or one that skipped them — gets the same mask as one that sends
 * the defaults explicitly.
 */
struct DesktopMaskEdgeTuning {
  double feather_height_fraction = 0.010;
  double erode_height_fraction = 0.002;
  double solidify_slope = 6.0;
  double solidify_midpoint = 0.55;
  double foreground_gamma = 1.0;
};

/** Subset of `BackgroundBlurConfig` the desktop compositor can act on. */
struct DesktopBlurConfig {
  double blur_sigma = 128.0;
  double background_obscure_opacity = 0.1;
  /** `CameraBackgroundMode.channelId`: "blur" or "image". */
  std::string background_mode = "blur";
  std::string replacement_image_path;
  DesktopMaskEdgeTuning mask_edge;
};

/**
 * A replacement background as it arrives on the channel. Each platform plugin
 * fills this from its own value type; the precedence between the fields is
 * shared, so Windows and Linux cannot drift apart.
 */
struct DesktopReplacementRequest {
  /** `backgroundMode == "blur"` wins outright and drops any image. */
  bool mode_is_blur = false;
  /** From `replacementImagePath`, falling back to `filePath`. */
  std::string path;
  /** From `imageBytes`; only consulted when [path] is empty. */
  std::vector<uint8_t> bytes;
};

/**
 * Why background effects are (not) usable, broken out condition by condition.
 *
 * `isBackgroundBlurReady` collapses all of this into one bool, which makes a
 * false answer impossible to act on; this is the same answer with its reasoning
 * intact, for logs and the debug UI.
 */
struct DesktopReadiness {
  /** Set at plugin registration; empty means the model can never be found. */
  std::string models_dir;
  /** Where the segmenter was looked for; empty when [models_dir] is unset. */
  std::string model_path;
  bool model_file_found = false;
  /** False when the library was built without TensorFlow Lite. */
  bool tflite_compiled_in = false;
  bool engine_created = false;
  /** Engine exists and the model loaded. */
  bool engine_ready = false;
  /** False when flutter_webrtc headers were missing at build time. */
  bool frame_tap_compiled_in = false;
  bool webrtc_instance_found = false;
  /** Whether processed frames reach the user yet (kDesktopFramePipelineReady). */
  bool frame_pipeline_enabled = false;
  /** What `isBackgroundBlurReady` answers. */
  bool ready = false;
  /** The first blocking condition, phrased for a human. Empty when [ready]. */
  std::string reason;
};

/** Native segmenter state for the Dart debug UI (`getSegmentationModel`). */
struct DesktopSegmentationModelInfo {
  /** `SegmentationModelPreference.channelId`; empty when no model is loaded. */
  std::string model;
  std::string backend;
  /** Desktop bundles a single model, so the choice is never user-driven. */
  bool forced = true;
  bool supported = false;
  /** [DesktopReadiness::reason]; empty when effects are usable. */
  std::string reason;
};

class DesktopBackgroundBlur {
 public:
  static DesktopBackgroundBlur& Instance();

  DesktopMethodResult Handle(const std::string& method,
                             const std::string& track_id);

  /** Directory containing bundled .tflite models (set at plugin register). */
  void SetModelsDirectory(std::string path);

  bool IsReady() const;

  /** Every readiness condition, with the first blocker named. */
  DesktopReadiness Readiness() const;

  /** Logs [Readiness] as one line per condition. */
  void LogReadiness(const char* context) const;

  /** Applies blur sigma, obscure opacity, mask shaping and background mode. */
  void SetConfig(const DesktopBlurConfig& config);

  DesktopBlurConfig Config() const;

  /**
   * Desktop bundles only `selfie_segmenter.tflite`, so the request is recorded
   * but the effective model does not change. Accepting it keeps Dart's
   * `setSegmentationModel` from throwing on platforms without a choice.
   */
  void SetSegmentationModel(const std::string& model);

  DesktopSegmentationModelInfo SegmentationModelInfo() const;

  /**
   * Decodes [path] and installs it as the virtual background.
   * Returns false when the file cannot be decoded, which the plugin reports as
   * the `IMAGE` channel error (same contract as Android and iOS).
   */
  bool SetReplacementImagePath(const std::string& path);

  /** As [SetReplacementImagePath], for encoded bytes from `imageBytes`. */
  bool SetReplacementImageBytes(const uint8_t* data, size_t size);

  /**
   * Resolves a channel request to one of the setters above, matching the
   * precedence Android and iOS use. Returns false only when a supplied image
   * could not be decoded.
   */
  bool ApplyReplacementRequest(const DesktopReplacementRequest& request);

  void ClearReplacementImage();

  /**
   * Segments and composites one camera frame, writing the result to [out].
   *
   * Returns false when the frame should be passed through unchanged — no
   * engine, not ready, or the engine declined it. Called on the WebRTC capture
   * thread, so it must not block on anything slow beyond the inference itself.
   */
  bool ProcessI420(int width,
                   int height,
                   int rotation_degrees,
                   const uint8_t* src_y,
                   int stride_y,
                   const uint8_t* src_u,
                   int stride_u,
                   const uint8_t* src_v,
                   int stride_v,
                   ProcessedI420* out);

 private:
  DesktopBackgroundBlur() = default;

  /** Caller must hold the backend lock. */
  bool InstallReplacementLocked(const DecodedImage& image);

  /** As [Readiness]; caller must hold the backend lock. */
  DesktopReadiness ReadinessLocked() const;

  /** As [LogReadiness]; caller must hold the backend lock. */
  void LogReadinessLocked(const char* context) const;

  /** Re-pushes config and replacement image after the engine is (re)created. */
  void ApplyStateToEngineLocked();

  std::string models_dir_;
  std::string ResolveModelPath(const std::string& file_name) const;
};

}  // namespace meet_video_effects

#endif  // MEET_DESKTOP_BACKGROUND_BLUR_H_
