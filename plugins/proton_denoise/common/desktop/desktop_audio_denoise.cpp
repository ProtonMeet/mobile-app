/*
 * Copyright (c) 2026 Proton AG
 *
 * Desktop (Linux/Windows) backend for `me.proton.meet/denoise` and legacy `proton_denoise`.
 *
 * Effects channel: attach/detach records track + type; RNNoise handle is enabled for rnnoise.
 * Live capture hook still depends on flutter_webrtc desktop audio processing (same as mobile).
 * Legacy channel: direct RNNoise frame API for tests/tools.
 */

#include "desktop_audio_denoise.h"

#include "proton_rnnoise_api.h"

#include <mutex>
#include <unordered_map>
#include <utility>

#ifdef _WIN32
#include <windows.h>
#else
#include <dlfcn.h>
#endif

namespace proton_denoise {
namespace {

constexpr char kEffectsChannel[] = "me.proton.meet/denoise";
constexpr char kLegacyChannel[] = "proton_denoise";

ProtonRnnoiseHandle* g_rnnoise = nullptr;
std::mutex g_mutex;
std::unordered_map<std::string, std::string> g_attached;  // trackId -> type id
std::string g_primary_track;

#ifdef _WIN32
using FlutterWebRtcGetInstanceFn = void* (*)();
static FlutterWebRtcGetInstanceFn LoadWebRtcGetInstance() {
  HMODULE mod = GetModuleHandleA("flutter_webrtc_plugin.dll");
  if (!mod) {
    return nullptr;
  }
  return reinterpret_cast<FlutterWebRtcGetInstanceFn>(
      GetProcAddress(mod, "FlutterWebRTCPluginSharedInstance"));
}
#else
using FlutterWebRtcGetInstanceFn = void* (*)();

static constexpr char kFlutterWebRtcPluginSo[] = "libflutter_webrtc_plugin.so";
static constexpr char kFlutterWebRtcSharedInstanceSym[] =
    "flutter_webrtc_plugin_get_shared_instance";

static FlutterWebRtcGetInstanceFn LoadWebRtcGetInstance() {
  void* sym = dlsym(RTLD_DEFAULT, kFlutterWebRtcSharedInstanceSym);
  if (sym) {
    return reinterpret_cast<FlutterWebRtcGetInstanceFn>(sym);
  }
  // nosemgrep
  void* handle = dlopen(kFlutterWebRtcPluginSo, RTLD_NOW | RTLD_NOLOAD);
  if (!handle) {
    // nosemgrep
    handle = dlopen(kFlutterWebRtcPluginSo, RTLD_NOW);
  }
  if (!handle) {
    return nullptr;
  }
  sym = dlsym(handle, kFlutterWebRtcSharedInstanceSym);
  return sym ? reinterpret_cast<FlutterWebRtcGetInstanceFn>(sym) : nullptr;
}
#endif

}  // namespace

DesktopAudioDenoise& DesktopAudioDenoise::Instance() {
  static DesktopAudioDenoise instance;
  return instance;
}

bool DesktopAudioDenoise::WebRtcAvailable() const {
  auto get_instance = LoadWebRtcGetInstance();
  return get_instance != nullptr && get_instance() != nullptr;
}

void DesktopAudioDenoise::EnsureRnnoiseHandle() {
  if (g_rnnoise == nullptr) {
    g_rnnoise = proton_rnnoise_create();
  }
}

void DesktopAudioDenoise::DestroyRnnoiseHandle() {
  if (g_rnnoise != nullptr) {
    proton_rnnoise_destroy(g_rnnoise);
    g_rnnoise = nullptr;
  }
}

bool DesktopAudioDenoise::IsRnnoiseReady() const {
  std::lock_guard<std::mutex> lock(g_mutex);
  return g_rnnoise != nullptr;
}

DesktopMethodResult DesktopAudioDenoise::Handle(
    const std::string& channel,
    const std::string& method,
    const std::string& track_id,
    const std::string& type_id,
    bool enabled_flag) {
  if (channel == kEffectsChannel) {
    return HandleEffectsChannel(method, track_id, type_id);
  }
  if (channel == kLegacyChannel) {
    return HandleLegacyChannel(method, enabled_flag);
  }
  DesktopMethodResult result;
  result.success = false;
  result.error_code = "CHANNEL";
  result.error_message = "Unknown channel";
  return result;
}

DesktopMethodResult DesktopAudioDenoise::HandleEffectsChannel(
    const std::string& method,
    const std::string& track_id,
    const std::string& type_id) {
  DesktopMethodResult result;
  std::lock_guard<std::mutex> lock(g_mutex);

  if (method == "listDenoiseTypes") {
    const bool rnnoise_ready = g_rnnoise != nullptr;
    result.success = true;
    result.json_list_payload =
        R"([{"id":"rnnoise","displayName":"RNNoise","isReady":)"
        + std::string(rnnoise_ready ? "true" : "false") +
        R"(},{"id":"deepfilter","displayName":"DeepFilter 3","isReady":false})"
        R"(,{"id":"deepfilter2","displayName":"DeepFilter 2","isReady":false})"
        R"(,{"id":"dtln-rs","displayName":"DTLN","isReady":false}])";
    return result;
  }

  if (method == "isTypeReady") {
    result.bool_value = (type_id == "rnnoise" && g_rnnoise != nullptr);
    return result;
  }

  if (method == "attach") {
    if (!WebRtcAvailable()) {
      result.success = false;
      result.error_code = "WEBRTC_NOT_READY";
      result.error_message =
          "FlutterWebRTCPlugin handler not initialized yet — retry after the "
          "engine settles";
      return result;
    }
    if (track_id.empty() || type_id.empty()) {
      result.success = false;
      result.error_code = "ARGS";
      result.error_message = "trackId and type required";
      return result;
    }
    if (type_id == "deepfilter" || type_id == "deepfilter2") {
      result.success = false;
      result.error_code = "NOT_READY";
      result.error_message = "DeepFilter is not available on desktop yet";
      return result;
    }
    if (type_id == "dtln-rs") {
      result.success = false;
      result.error_code = "NOT_READY";
      result.error_message = "DTLN is not available on desktop yet";
      return result;
    }
    if (type_id != "rnnoise") {
      result.success = false;
      result.error_code = "ARGS";
      result.error_message = "Unknown denoise type";
      return result;
    }
    EnsureRnnoiseHandle();
    if (g_rnnoise == nullptr) {
      result.success = false;
      result.error_code = "NOT_READY";
      result.error_message = "RNNoise failed to initialize";
      return result;
    }
    for (auto it = g_attached.begin(); it != g_attached.end();) {
      if (it->first != track_id) {
        it = g_attached.erase(it);
      } else {
        ++it;
      }
    }
    g_attached[track_id] = type_id;
    g_primary_track = track_id;
    proton_rnnoise_set_enabled(g_rnnoise, 1);
    return result;
  }

  if (method == "detach") {
    if (track_id.empty()) {
      result.success = false;
      result.error_code = "ARGS";
      result.error_message = "trackId required";
      return result;
    }
    g_attached.erase(track_id);
    if (g_primary_track == track_id) {
      g_primary_track.clear();
      if (g_rnnoise != nullptr) {
        proton_rnnoise_set_enabled(g_rnnoise, 0);
      }
    }
    return result;
  }

  result.success = false;
  result.error_code = "NOT_IMPLEMENTED";
  result.error_message = method;
  return result;
}

DesktopMethodResult DesktopAudioDenoise::HandleLegacyChannel(
    const std::string& method,
    bool enabled_flag) {
  DesktopMethodResult result;
  std::lock_guard<std::mutex> lock(g_mutex);

  if (method == "create") {
    DestroyRnnoiseHandle();
    EnsureRnnoiseHandle();
    result.bool_value = g_rnnoise != nullptr;
    return result;
  }

  if (method == "destroy") {
    DestroyRnnoiseHandle();
    g_attached.clear();
    g_primary_track.clear();
    return result;
  }

  if (method == "getFrameSize") {
    result.int_value = proton_rnnoise_get_frame_size();
    return result;
  }

  if (method == "setEnabled") {
    if (g_rnnoise == nullptr) {
      result.success = false;
      result.error_code = "invalid_state";
      result.error_message = "RNNoise not initialized";
      return result;
    }
    proton_rnnoise_set_enabled(g_rnnoise, enabled_flag ? 1 : 0);
    return result;
  }

  if (method == "isEnabled") {
    result.bool_value =
        g_rnnoise != nullptr && proton_rnnoise_is_enabled(g_rnnoise) != 0;
    return result;
  }

  result.success = false;
  result.error_code = "NOT_IMPLEMENTED";
  result.error_message = method;
  return result;
}

DesktopMethodResult DesktopAudioDenoise::ProcessFrame(float* samples,
                                                      size_t sample_count,
                                                      int channels) {
  DesktopMethodResult result;
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_rnnoise == nullptr || samples == nullptr || sample_count == 0 ||
      channels <= 0) {
    result.success = false;
    result.error_code = "invalid_state";
    result.error_message = "RNNoise not initialized";
    return result;
  }
  result.float_value = proton_rnnoise_process_interleaved(
      g_rnnoise, samples, sample_count, channels);
  return result;
}

}  // namespace proton_denoise

