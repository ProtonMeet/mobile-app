/*
 * Copyright (c) 2026 Proton AG
 */

#include "desktop_background_blur.h"

#include "meet_video_effects.h"

#include <mutex>
#include <unordered_map>

#ifdef _WIN32
#include <windows.h>
#else
#include <dlfcn.h>
#endif

namespace meet_video_effects {
namespace {

MeetVideoEffectsEngine *g_engine = nullptr;
std::mutex g_mutex;
std::unordered_map<std::string, bool> g_attached_tracks;

#ifdef _WIN32
using FlutterWebRtcGetInstanceFn = void *(*)();
static FlutterWebRtcGetInstanceFn LoadWebRtcGetInstance() {
  HMODULE mod = GetModuleHandleA("flutter_webrtc_plugin.dll");
  if (!mod)
    return nullptr;
  return reinterpret_cast<FlutterWebRtcGetInstanceFn>(
      GetProcAddress(mod, "FlutterWebRTCPluginSharedInstance"));
}
#else
using FlutterWebRtcGetInstanceFn = void *(*)();

// Fixed soname bundled with the Flutter embedder; never derived from user
// input.
static constexpr char kFlutterWebRtcPluginSo[] = "libflutter_webrtc_plugin.so";
static constexpr char kFlutterWebRtcSharedInstanceSym[] =
    "flutter_webrtc_plugin_get_shared_instance";

static FlutterWebRtcGetInstanceFn LoadWebRtcGetInstance() {
  void *sym = dlsym(RTLD_DEFAULT, kFlutterWebRtcSharedInstanceSym);
  if (sym) {
    return reinterpret_cast<FlutterWebRtcGetInstanceFn>(sym);
  }
  // nosemgrep
  void *handle = dlopen(kFlutterWebRtcPluginSo, RTLD_NOW | RTLD_NOLOAD);
  if (!handle) {
    // nosemgrep
    handle = dlopen(kFlutterWebRtcPluginSo, RTLD_NOW);
  }
  if (!handle)
    return nullptr;
  sym = dlsym(handle, kFlutterWebRtcSharedInstanceSym);
  return sym ? reinterpret_cast<FlutterWebRtcGetInstanceFn>(sym) : nullptr;
}
#endif

static bool WebRtcTrackExists(const std::string &track_id) {
  // Track lookup uses flutter_webrtc's exported singleton. Full frame
  // processing requires a desktop VideoProcessingAdapter in flutter_webrtc
  // (same as iOS); until then we validate the track id and mark attach state
  // for Dart parity.
  auto get_instance = LoadWebRtcGetInstance();
  if (!get_instance)
    return false;
  void *webrtc = get_instance();
  return webrtc != nullptr && !track_id.empty();
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
  const std::string model_path = ResolveModelPath("selfie_segmenter.tflite");
  if (!model_path.empty()) {
    g_engine = meet_video_effects_create(model_path.c_str());
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

DesktopMethodResult DesktopBackgroundBlur::Handle(const std::string &method,
                                                  const std::string &track_id) {
  DesktopMethodResult result;
  std::lock_guard<std::mutex> lock(g_mutex);

  if (method == "isImplementationReady" || method == "isBackgroundBlurReady") {
    result.bool_value = meet_video_effects_is_ready(g_engine);
    return result;
  }

  if (method == "attach" || method == "attachBackgroundBlur") {
    if (!meet_video_effects_is_ready(g_engine)) {
      result.success = false;
      result.error_code = "NOT_READY";
      result.error_message =
          "TensorFlow Lite model not loaded (set TFLITE_ROOT at build time)";
      return result;
    }
    if (!WebRtcTrackExists(track_id)) {
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
