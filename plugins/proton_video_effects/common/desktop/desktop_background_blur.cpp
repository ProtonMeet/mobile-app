/*
 * Copyright (c) 2026 Proton AG
 */

#include "desktop_background_blur.h"

#include "desktop_image_decoder.h"
#include "desktop_webrtc_instance.h"
#include "meet_video_effects.h"

#ifdef MEET_VIDEO_EFFECTS_HAS_WEBRTC
#include "desktop_frame_tap.h"
#include "desktop_webrtc_internals.h"
#endif

#include "desktop_log.h"

#include <fstream>
#include <mutex>
#include <unordered_map>
#include <utility>

namespace meet_video_effects {
namespace {

MeetVideoEffectsEngine *g_engine = nullptr;
std::mutex g_mutex;
std::unordered_map<std::string, bool> g_attached_tracks;
DesktopBlurConfig g_config;

// Dart may pick a background before the engine exists (or across a rebuild
// when the models directory changes), so the decoded pixels are held here and
// installed as soon as there is an engine to take them.
DecodedImage g_pending_replacement;

// The only model bundled with the desktop plugin; matches
// SegmentationModelPreference.single (square selfie segmenter).
constexpr char kBundledModel[] = "single";
constexpr char kBundledModelFile[] = "selfie_segmenter.tflite";
std::string g_requested_model = kBundledModel;

// Whether processed frames actually reach remote participants.
//
// Desktop flutter_webrtc has no VideoProcessingAdapter to edit camera frames in
// place, as Apple and Android do, so blur here works by publishing a *second*
// track: the frame tap reads the camera track, the engine composites, and
// CreateProcessedVideoTrack feeds a custom source that Dart publishes in the
// camera track's place. Dart must therefore also honour
// BackgroundBlurTrackProcessor.processedTrack; without that the effect would be
// computed and thrown away, which is what this gate used to prevent.
// See native/README.md.
constexpr bool kDesktopFramePipelineReady = true;

static bool WebRtcTrackExists(const std::string &track_id) {
  // Track lookup uses flutter_webrtc's exported singleton. Full frame
  // processing requires a desktop VideoProcessingAdapter in flutter_webrtc
  // (same as iOS); until then we validate the track id and mark attach state
  // for Dart parity.
  return GetFlutterWebRtcSharedInstance() != nullptr && !track_id.empty();
}

} // namespace

DesktopBackgroundBlur &DesktopBackgroundBlur::Instance() {
  static DesktopBackgroundBlur instance;
  return instance;
}

void DesktopBackgroundBlur::SetModelsDirectory(std::string path) {
  std::lock_guard<std::mutex> lock(g_mutex);
  models_dir_ = std::move(path);
  if (g_engine) {
    meet_video_effects_destroy(g_engine);
    g_engine = nullptr;
  }
  const std::string model_path = ResolveModelPath(kBundledModelFile);
  if (!model_path.empty()) {
    g_engine = meet_video_effects_create(model_path.c_str());
  }
  MEET_VE_LOG() << "setModelsDirectory: dir='" << models_dir_ << "' modelPath='"
                << model_path << "' engineCreated="
                << (g_engine ? "true" : "false") << " engineReady="
                << (g_engine && meet_video_effects_is_ready(g_engine) ? "true"
                                                                      : "false")
                << " tfliteCompiledIn="
                << (meet_video_effects_has_tflite() ? "true" : "false");
  ApplyStateToEngineLocked();
}

void DesktopBackgroundBlur::ApplyStateToEngineLocked() {
  if (!g_engine)
    return;
  meet_video_effects_set_blur_config(
      g_engine, static_cast<float>(g_config.blur_sigma),
      static_cast<float>(g_config.background_obscure_opacity));
  meet_video_effects_set_mask_edge_tuning(
      g_engine, static_cast<float>(g_config.mask_edge.feather_height_fraction),
      static_cast<float>(g_config.mask_edge.erode_height_fraction),
      static_cast<float>(g_config.mask_edge.solidify_slope),
      static_cast<float>(g_config.mask_edge.solidify_midpoint),
      static_cast<float>(g_config.mask_edge.foreground_gamma));
  meet_video_effects_set_background_mode(
      g_engine, g_config.background_mode == "image"
                    ? kMeetVideoEffectsBackgroundImage
                    : kMeetVideoEffectsBackgroundBlur);
  if (g_pending_replacement.valid()) {
    meet_video_effects_set_replacement_image(
        g_engine, g_pending_replacement.rgba.data(),
        g_pending_replacement.width, g_pending_replacement.height);
    g_pending_replacement = {};
  }
}

std::string
DesktopBackgroundBlur::ResolveModelPath(const std::string &file_name) const {
  if (models_dir_.empty())
    return {};
  if (models_dir_.back() == '/' || models_dir_.back() == '\\') {
    return models_dir_ + file_name;
  }
  return models_dir_ + "/" + file_name;
}

bool DesktopBackgroundBlur::IsReady() const {
  std::lock_guard<std::mutex> lock(g_mutex);
  return g_engine != nullptr && meet_video_effects_is_ready(g_engine);
}

DesktopReadiness DesktopBackgroundBlur::Readiness() const {
  std::lock_guard<std::mutex> lock(g_mutex);
  return ReadinessLocked();
}

void DesktopBackgroundBlur::LogReadiness(const char *context) const {
  std::lock_guard<std::mutex> lock(g_mutex);
  LogReadinessLocked(context);
}

DesktopReadiness DesktopBackgroundBlur::ReadinessLocked() const {
  DesktopReadiness r;
  r.tflite_compiled_in = meet_video_effects_has_tflite();
  r.frame_pipeline_enabled = kDesktopFramePipelineReady;
  r.webrtc_instance_found = GetFlutterWebRtcSharedInstance() != nullptr;
#ifdef MEET_VIDEO_EFFECTS_HAS_WEBRTC
  r.frame_tap_compiled_in = true;
#endif

  r.models_dir = models_dir_;
  r.model_path = ResolveModelPath(kBundledModelFile);
  r.engine_created = g_engine != nullptr;
  r.engine_ready = g_engine != nullptr && meet_video_effects_is_ready(g_engine);

  if (!r.model_path.empty()) {
    std::ifstream f(r.model_path, std::ios::binary);
    r.model_file_found = f.good();
  }

  // Ordered so the first failure reported is the one to fix first: a missing
  // model makes everything downstream fail too.
  if (!r.tflite_compiled_in) {
    r.reason =
        "built without TensorFlow Lite — the vendored runtime under "
        "native/third_party/tflite was not picked up (see native/README.md)";
  } else if (r.models_dir.empty()) {
    r.reason = "models directory was never set by the plugin registrar";
  } else if (!r.model_file_found) {
    r.reason = "selfie_segmenter.tflite not found at " + r.model_path;
  } else if (!r.engine_created) {
    r.reason = "engine failed to construct from " + r.model_path;
  } else if (!r.engine_ready) {
    r.reason = "model loaded but the interpreter is not ready";
  } else if (!r.frame_tap_compiled_in) {
    r.reason =
        "frame tap not compiled — flutter_webrtc headers were missing at build "
        "time";
  } else if (!r.webrtc_instance_found) {
    r.reason = "flutter_webrtc shared instance not found";
  } else if (!r.frame_pipeline_enabled) {
    r.reason =
        "engine is healthy, but processed frames are not routed anywhere yet: "
        "desktop flutter_webrtc exposes no seam to publish them, so the "
        "control stays disabled on purpose (kDesktopFramePipelineReady)";
  } else {
    r.ready = true;
  }
  return r;
}

void DesktopBackgroundBlur::LogReadinessLocked(const char *context) const {
  const DesktopReadiness r = ReadinessLocked();
  MEET_VE_LOG() << context << ": ready=" << (r.ready ? "true" : "false");
  MEET_VE_LOG() << context << ":   tfliteCompiledIn="
                << (r.tflite_compiled_in ? "true" : "false")
                << " engineCreated=" << (r.engine_created ? "true" : "false")
                << " engineReady=" << (r.engine_ready ? "true" : "false");
  MEET_VE_LOG() << context << ":   modelsDir='" << r.models_dir
                << "' modelPath='" << r.model_path << "' modelFileFound="
                << (r.model_file_found ? "true" : "false");
  MEET_VE_LOG() << context << ":   frameTapCompiledIn="
                << (r.frame_tap_compiled_in ? "true" : "false")
                << " webrtcInstanceFound="
                << (r.webrtc_instance_found ? "true" : "false")
                << " framePipelineEnabled="
                << (r.frame_pipeline_enabled ? "true" : "false");
  if (!r.ready) {
    MEET_VE_LOG() << context << ":   blocked by -> " << r.reason;
  }
#ifdef MEET_VIDEO_EFFECTS_HAS_WEBRTC
  // Whether the protected members needed to publish a processed track are
  // actually reachable; factoryFound=false would mean the layout assumption
  // behind desktop_webrtc_internals.cpp no longer holds.
  LogWebRtcInternals(context);
#endif
}

void DesktopBackgroundBlur::SetConfig(const DesktopBlurConfig &config) {
  std::lock_guard<std::mutex> lock(g_mutex);
  // Preserve the installed image: a config that only flips the mode carries no
  // path, and re-decoding on every slider change would be wasteful anyway.
  const std::string previous_path = g_config.replacement_image_path;
  g_config = config;
  if (g_config.replacement_image_path.empty()) {
    g_config.replacement_image_path = previous_path;
  }
  ApplyStateToEngineLocked();
}

DesktopBlurConfig DesktopBackgroundBlur::Config() const {
  std::lock_guard<std::mutex> lock(g_mutex);
  return g_config;
}

void DesktopBackgroundBlur::SetSegmentationModel(const std::string &model) {
  std::lock_guard<std::mutex> lock(g_mutex);
  g_requested_model = model.empty() ? kBundledModel : model;
}

DesktopSegmentationModelInfo DesktopBackgroundBlur::SegmentationModelInfo()
    const {
  std::lock_guard<std::mutex> lock(g_mutex);
  DesktopSegmentationModelInfo info;
  // Reports what the engine can do, not whether frames reach it: this feeds the
  // debug screens, where knowing the model loaded is the useful signal. The
  // end-to-end answer is isBackgroundBlurReady.
  info.supported = g_engine != nullptr && meet_video_effects_is_ready(g_engine);
  info.model = info.supported ? kBundledModel : std::string();
  info.backend = "tflite";
  // Carries the end-to-end blocker so the debug UI can say more than "not
  // ready" without another round trip.
  info.reason = ReadinessLocked().reason;
  return info;
}

bool DesktopBackgroundBlur::SetReplacementImagePath(const std::string &path) {
  if (path.empty()) {
    ClearReplacementImage();
    return true;
  }
  // Decode outside the lock: it touches the filesystem and a large image can
  // take milliseconds, which would otherwise stall the capture thread.
  const DecodedImage image = DecodeImageFile(path);
  if (!image.valid())
    return false;

  std::lock_guard<std::mutex> lock(g_mutex);
  g_config.replacement_image_path = path;
  return InstallReplacementLocked(image);
}

bool DesktopBackgroundBlur::SetReplacementImageBytes(const uint8_t *data,
                                                     size_t size) {
  if (!data || size == 0) {
    ClearReplacementImage();
    return true;
  }
  const DecodedImage image = DecodeImageBytes(data, size);
  if (!image.valid())
    return false;

  std::lock_guard<std::mutex> lock(g_mutex);
  g_config.replacement_image_path.clear();
  return InstallReplacementLocked(image);
}

bool DesktopBackgroundBlur::InstallReplacementLocked(
    const DecodedImage &image) {
  if (!g_engine) {
    // The engine is created once the models directory is known; keep the
    // decoded pixels so attach can install them.
    g_pending_replacement = image;
    return true;
  }
  g_pending_replacement = {};
  return meet_video_effects_set_replacement_image(
      g_engine, image.rgba.data(), image.width, image.height);
}

bool DesktopBackgroundBlur::ApplyReplacementRequest(
    const DesktopReplacementRequest &request) {
  if (request.mode_is_blur) {
    ClearReplacementImage();
    return true;
  }
  if (!request.path.empty()) {
    return SetReplacementImagePath(request.path);
  }
  if (!request.bytes.empty()) {
    return SetReplacementImageBytes(request.bytes.data(),
                                    request.bytes.size());
  }
  // Image mode with nothing attached means "keep what is installed", not
  // "clear". Presets arrive through setReplacementBackgroundImageBytes before
  // attach and carry no path in the config, so clearing here dropped the image
  // and left the engine falling back to blur with image mode still selected.
  return true;
}

void DesktopBackgroundBlur::ClearReplacementImage() {
  std::lock_guard<std::mutex> lock(g_mutex);
  g_config.replacement_image_path.clear();
  g_pending_replacement = {};
  if (g_engine) {
    meet_video_effects_set_replacement_image(g_engine, nullptr, 0, 0);
  }
}

bool DesktopBackgroundBlur::ProcessI420(
    int width, int height, int rotation_degrees, const uint8_t *src_y,
    int stride_y, const uint8_t *src_u, int stride_u, const uint8_t *src_v,
    int stride_v, ProcessedI420 *out) {
  if (!out || !src_y || !src_u || !src_v || width <= 0 || height <= 0) {
    return false;
  }

  // Shares the lock with the config setters so a slider change cannot land
  // mid-inference. Config calls are rare, so the capture thread is not
  // contended in practice.
  std::lock_guard<std::mutex> lock(g_mutex);
  if (!g_engine || !meet_video_effects_is_ready(g_engine)) {
    return false;
  }
  // Desktop keeps the tap and the processed track running for the whole call,
  // so attach state — not the tap's existence — is what decides whether an
  // effect is applied. Declining here makes the caller publish the camera
  // frame untouched, which is how detach takes effect without a republish.
  if (g_attached_tracks.empty()) {
    return false;
  }

  return meet_video_effects_process_i420(
      g_engine, width, height, rotation_degrees, src_y, stride_y, src_u,
      stride_u, src_v, stride_v, &out->y, &out->stride_y, &out->u,
      &out->stride_u, &out->v, &out->stride_v, &out->width, &out->height);
}

DesktopMethodResult DesktopBackgroundBlur::Handle(const std::string &method,
                                                  const std::string &track_id) {
  DesktopMethodResult result;
  std::lock_guard<std::mutex> lock(g_mutex);

  if (method == "isImplementationReady" || method == "isBackgroundBlurReady") {
    // Logged in full every time: a bare `false` here is the single most
    // confusing thing this plugin can tell Dart. The lock is already held, so
    // these have to be the *Locked variants.
    LogReadinessLocked(method.c_str());
    result.SetBool(ReadinessLocked().ready);
    return result;
  }

#ifdef MEET_VIDEO_EFFECTS_HAS_WEBRTC
  // Diagnostics for the desktop frame pipeline: they let the debug screen prove
  // camera frames reach the engine without going through `attach`, which stays
  // gated until processed frames are actually shown.
  if (method == "startFrameTap") {
    result.SetBool(DesktopFrameTap::Instance().Start(track_id));
    MEET_VE_LOG() << "startFrameTap: trackId=" << track_id
                  << " started=" << (result.bool_value ? "true" : "false");
    if (!result.bool_value) {
      LogReadinessLocked("startFrameTap");
    }
    return result;
  }
    // Creates the track Dart publishes in place of the camera track; the tap
    // feeds it. Separate from `startFrameTap` so the tap stays usable as a
    // pure diagnostic.
    if (method == "createProcessedTrack") {
      result.SetString(CreateProcessedVideoTrack());
      if (result.string_value.empty()) {
        result.success = false;
        result.error_code = "PROCESSED_TRACK";
        result.error_message =
            "could not create the processed video track; see the "
            "ProtonVideoEffects log for the failing condition";
        LogReadinessLocked("createProcessedTrack");
      }
      return result;
    }
    if (method == "destroyProcessedTrack") {
      DestroyProcessedVideoTrack();
      return result;
    }
    if (method == "stopFrameTap") {
      DesktopFrameTap::Instance().Stop(track_id);
    MEET_VE_LOG() << "stopFrameTap: trackId=" << track_id << " processedFrames="
                  << DesktopFrameTap::Instance().processed_frames()
                  << " passthroughFrames="
                  << DesktopFrameTap::Instance().passthrough_frames();
    return result;
  }
#endif

  if (method == "attach" || method == "attachBackgroundBlur") {
    MEET_VE_LOG() << "attach: trackId=" << track_id
                  << " mode=" << g_config.background_mode
                  << " blurSigma=" << g_config.blur_sigma;
    if (!kDesktopFramePipelineReady) {
      LogReadinessLocked("attach");
      result.success = false;
      result.error_code = "UNSUPPORTED";
      result.error_message = ReadinessLocked().reason;
      return result;
    }
    if (!meet_video_effects_is_ready(g_engine)) {
      result.success = false;
      result.error_code = "NOT_READY";
      result.error_message =
          "TensorFlow Lite segmentation model not loaded";
      return result;
    }
    if (!WebRtcTrackExists(track_id)) {
      MEET_VE_LOG() << "attach: track lookup failed trackId='" << track_id
                    << "' webrtcInstance="
                    << (GetFlutterWebRtcSharedInstance() ? "found" : "missing");
      result.success = false;
      result.error_code = "TRACK";
      result.error_message = "Local video track not found";
      return result;
    }
    g_attached_tracks[track_id] = true;
    return result;
  }

  if (method == "detach" || method == "detachBackgroundBlur") {
    g_attached_tracks.erase(track_id);
    return result;
  }

  result.success = false;
  result.error_code = "NOT_IMPLEMENTED";
  result.error_message = method;
  return result;
}

} // namespace meet_video_effects
