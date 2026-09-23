/*
 * Copyright (c) 2026 Proton AG
 * Windows lookup of flutter_webrtc's exported singleton.
 */

#include <windows.h>

#include "desktop_webrtc_instance.h"

namespace meet_video_effects {
namespace {

using FlutterWebRtcGetInstanceFn = flutter_webrtc_plugin::FlutterWebRTC *(*)();

// Fixed module name shipped by the Flutter embedder; never derived from user
// input. GetModuleHandle rather than LoadLibrary: if flutter_webrtc is not
// already loaded there is no instance to hand out.
constexpr char kFlutterWebRtcPluginDll[] = "flutter_webrtc_plugin.dll";
constexpr char kFlutterWebRtcSharedInstanceSym[] =
    "FlutterWebRTCPluginSharedInstance";

}  // namespace

flutter_webrtc_plugin::FlutterWebRTC *GetFlutterWebRtcSharedInstance() {
  HMODULE mod = GetModuleHandleA(kFlutterWebRtcPluginDll);
  if (!mod) return nullptr;
  auto get_instance = reinterpret_cast<FlutterWebRtcGetInstanceFn>(
      GetProcAddress(mod, kFlutterWebRtcSharedInstanceSym));
  return get_instance ? get_instance() : nullptr;
}

}  // namespace meet_video_effects
