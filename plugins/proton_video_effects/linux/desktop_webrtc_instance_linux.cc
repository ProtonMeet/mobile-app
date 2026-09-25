/*
 * Copyright (c) 2026 Proton AG
 * Linux lookup of flutter_webrtc's exported singleton.
 */

#include <dlfcn.h>

#include "desktop_webrtc_instance.h"

namespace meet_video_effects {
namespace {

using FlutterWebRtcGetInstanceFn = flutter_webrtc_plugin::FlutterWebRTC *(*)();

// Fixed soname bundled with the Flutter embedder; never derived from user
// input.
constexpr char kFlutterWebRtcPluginSo[] = "libflutter_webrtc_plugin.so";
constexpr char kFlutterWebRtcSharedInstanceSym[] =
    "flutter_webrtc_plugin_get_shared_instance";

FlutterWebRtcGetInstanceFn LoadGetInstance() {
  // Already-loaded plugins resolve straight out of the global scope.
  if (void *sym = dlsym(RTLD_DEFAULT, kFlutterWebRtcSharedInstanceSym)) {
    return reinterpret_cast<FlutterWebRtcGetInstanceFn>(sym);
  }
  // nosemgrep
  void *handle = dlopen(kFlutterWebRtcPluginSo, RTLD_NOW | RTLD_NOLOAD);
  if (!handle) {
    // nosemgrep
    handle = dlopen(kFlutterWebRtcPluginSo, RTLD_NOW);
  }
  if (!handle) return nullptr;
  void *sym = dlsym(handle, kFlutterWebRtcSharedInstanceSym);
  return sym ? reinterpret_cast<FlutterWebRtcGetInstanceFn>(sym) : nullptr;
}

}  // namespace

flutter_webrtc_plugin::FlutterWebRTC *GetFlutterWebRtcSharedInstance() {
  FlutterWebRtcGetInstanceFn get_instance = LoadGetInstance();
  return get_instance ? get_instance() : nullptr;
}

}  // namespace meet_video_effects
