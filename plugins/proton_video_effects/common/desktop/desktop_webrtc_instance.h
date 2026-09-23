/*
 * Copyright (c) 2026 Proton AG
 * Access to flutter_webrtc's exported singleton from the desktop plugin.
 */

#ifndef MEET_DESKTOP_WEBRTC_INSTANCE_H_
#define MEET_DESKTOP_WEBRTC_INSTANCE_H_

namespace flutter_webrtc_plugin {
class FlutterWebRTC;
}  // namespace flutter_webrtc_plugin

namespace meet_video_effects {

/**
 * Returns flutter_webrtc's shared plugin instance, or nullptr when the plugin
 * is not loaded or does not export it.
 *
 * Resolved at runtime rather than linked: the Flutter embedder decides plugin
 * load order, and the accessor is spelled differently per platform
 * (`FlutterWebRTCPluginSharedInstance` on Windows,
 * `flutter_webrtc_plugin_get_shared_instance` on Linux), so each platform
 * directory supplies its own implementation.
 *
 * Only `virtual` members of the returned object may be called.
 * flutter_webrtc's plugin library exports just the two registration symbols and
 * no C++ methods, so a non-virtual call would compile and then fail to link.
 * This is the same constraint livekit_client works within.
 */
flutter_webrtc_plugin::FlutterWebRTC* GetFlutterWebRtcSharedInstance();

}  // namespace meet_video_effects

#endif  // MEET_DESKTOP_WEBRTC_INSTANCE_H_
