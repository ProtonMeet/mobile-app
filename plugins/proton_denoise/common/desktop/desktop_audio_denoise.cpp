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

#include <chrono>
#include <mutex>
#include <unordered_map>
#include <utility>
#include <vector>

#ifdef _WIN32
#include <windows.h>
#else
#include <dlfcn.h>
#endif

namespace proton_denoise {
namespace {

constexpr char kEffectsChannel[] = "me.proton.meet/denoise";
constexpr char kLegacyChannel[] = "proton_denoise";

// Must match DenoiseType.id in lib/denoise_type.dart.
constexpr char kRnnoiseId[] = "rnnoise";
constexpr char kDeepFilterId[] = "deepfilter";
constexpr char kDtlnRsId[] = "dtln-rs";

constexpr char kDesktopUnsupported[] = "not implemented on desktop yet";

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
  return proton_rnnoise_get_frame_size() > 0;
}

std::vector<DenoiseTypeEntry> DesktopAudioDenoise::ListDenoiseTypes() const {
  std::lock_guard<std::mutex> lock(g_mutex);

  DenoiseTypeEntry rnnoise;
  rnnoise.id = kRnnoiseId;
  rnnoise.display_name = "RNNoise";
  // The handle is created lazily on attach, so readiness reflects the linked
  // library rather than the current session.
  rnnoise.is_ready = proton_rnnoise_get_frame_size() > 0;
  rnnoise.status = rnnoise.is_ready ? "ok" : "rnnoise library not linked";

  DenoiseTypeEntry deepfilter;
  deepfilter.id = kDeepFilterId;
  deepfilter.display_name = "DeepFilter 3";
  deepfilter.status = kDesktopUnsupported;

  DenoiseTypeEntry dtln;
  dtln.id = kDtlnRsId;
  dtln.display_name = "DTLN";
  dtln.status = kDesktopUnsupported;

  return {rnnoise, deepfilter, dtln};
}

std::vector<DenoiseWarmUpEntry> DesktopAudioDenoise::WarmUp(
    const std::string& type_id) {
  std::vector<DenoiseWarmUpEntry> out;

  for (const auto& type : ListDenoiseTypes()) {
    if (!type_id.empty() && type.id != type_id) {
      continue;
    }

    DenoiseWarmUpEntry entry;
    entry.id = type.id;

    if (type.id != kRnnoiseId) {
      entry.status = type.status;
      out.push_back(entry);
      continue;
    }

    const auto started = std::chrono::steady_clock::now();
    {
      std::lock_guard<std::mutex> lock(g_mutex);
      EnsureRnnoiseHandle();
      const int frame_size = proton_rnnoise_get_frame_size();
      if (g_rnnoise != nullptr && frame_size > 0) {
        // One silent frame forces model/state allocation off the capture path.
        std::vector<float> silence(static_cast<size_t>(frame_size), 0.f);
        proton_rnnoise_process_interleaved(g_rnnoise, silence.data(),
                                           silence.size(), 1);
        entry.warm_up_ok = true;
        entry.status = "ok";
      } else {
        entry.status = "rnnoise failed to initialize";
      }
    }
    entry.warm_up_ms = static_cast<int>(
        std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - started)
            .count());
    out.push_back(entry);
  }

  return out;
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

  // Payload is built by the platform plugin from ListDenoiseTypes().
  if (method == "listDenoiseTypes" || method == "diagnoseDenoise" ||
      method == "warmUpDenoise") {
    result.success = true;
    return result;
  }

  // Readiness must reflect the linked library, not the lazily created handle:
  // Dart checks isTypeReady before attach, which is what creates the handle.
  if (method == "isTypeReady") {
    result.bool_value =
        (type_id == kRnnoiseId && proton_rnnoise_get_frame_size() > 0);
    return result;
  }

  // DeepFilter never attaches on desktop, so the attenuation limit is a no-op
  // rather than an error (Dart rethrows PlatformException here).
  if (method == "setDeepFilterAttenLim") {
    result.success = true;
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
    if (type_id == kDeepFilterId) {
      result.success = false;
      result.error_code = "NOT_READY";
      result.error_message = "DeepFilter is not available on desktop yet";
      return result;
    }
    if (type_id == kDtlnRsId) {
      result.success = false;
      result.error_code = "NOT_READY";
      result.error_message = "DTLN is not available on desktop yet";
      return result;
    }
    if (type_id != kRnnoiseId) {
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

