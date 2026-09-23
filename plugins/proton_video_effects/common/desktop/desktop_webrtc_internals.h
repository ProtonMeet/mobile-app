/*
 * Copyright (c) 2026 Proton AG
 * Reaches the parts of flutter_webrtc needed to publish a processed track.
 */

#ifndef MEET_DESKTOP_WEBRTC_INTERNALS_H_
#define MEET_DESKTOP_WEBRTC_INTERNALS_H_

#include <cstddef>
#include <cstdint>
#include <string>

namespace meet_video_effects {

/** Whether the stolen field offsets can be trusted. */
enum class WebRtcLayoutCheck {
  /** flutter_webrtc has not initialised yet, so a null factory proves nothing. */
  kInconclusive,
  /** Initialised and the factory read back non-null: the offsets are right. */
  kVerified,
  /** Initialised but the factory read back null: the offsets are wrong. */
  kMismatch,
};

/** What [ProbeWebRtcInternals] found, for logging and a pre-flight check. */
struct WebRtcInternals {
  /** flutter_webrtc's shared instance was available. */
  bool instance_found = false;
  /**
   * `EnsureWebRTCInitialized` has run.
   *
   * Read through the public virtual `audio_processing()`, which is assigned
   * immediately after `factory_` in that same function — so it answers
   * "is the factory constructed yet?" without depending on any field offset.
   */
  bool webrtc_initialized = false;
  /** The stolen `factory_` is non-null. */
  bool factory_found = false;
  /** How many local tracks flutter_webrtc currently knows about. */
  size_t local_track_count = 0;
  WebRtcLayoutCheck layout = WebRtcLayoutCheck::kInconclusive;
};

/**
 * Inspects flutter_webrtc's internal state without changing it.
 *
 * Publishing a processed video track needs `FlutterWebRTCBase::factory_` (to
 * build a custom video source) and `local_tracks_` (so Dart can resolve the new
 * track by id). Both are protected and the plugin library exports no C++
 * symbols, so they are reached with the pointer-to-member idiom — see the
 * implementation for why that is well-defined rather than a cast.
 *
 * That idiom does depend on FlutterWebRTCBase's field layout, so this doubles
 * as the pre-flight check — see [WebRtcLayoutCheck]. Note that `factory_` is
 * created lazily in `EnsureWebRTCInitialized`, not in the constructor, so
 * before flutter_webrtc is first used a null factory is expected rather than a
 * failure.
 */
WebRtcInternals ProbeWebRtcInternals();

/** Logs [ProbeWebRtcInternals] under the plugin's usual tag. */
void LogWebRtcInternals(const char* context);

/**
 * Creates a video track fed by [PushProcessedFrame] and registers it with
 * flutter_webrtc, returning its id (empty on failure).
 *
 * This is the piece desktop flutter_webrtc cannot do for us. The camera's own
 * source is owned inside libwebrtc and cannot be written to, so instead we make
 * a second, *custom* source that accepts injected frames, wrap it in a track,
 * and put that track in `local_tracks_` so Dart can resolve it by id and
 * publish it in place of the camera track.
 *
 * Requires [ProbeWebRtcInternals] to report [WebRtcLayoutCheck::kVerified];
 * callers must check that first.
 */
std::string CreateProcessedVideoTrack();

/**
 * Pushes one composited frame into the track from [CreateProcessedVideoTrack].
 *
 * Called on the WebRTC capture thread. The planes are copied into a new frame,
 * so they need only stay valid for the duration of the call. No-op when no
 * processed track exists.
 */
void PushProcessedFrame(int width,
                        int height,
                        const uint8_t* y,
                        int stride_y,
                        const uint8_t* u,
                        int stride_u,
                        const uint8_t* v,
                        int stride_v);

/** Unregisters and releases the processed track; safe if none exists. */
void DestroyProcessedVideoTrack();

/** Id of the live processed track, or empty. */
std::string ProcessedVideoTrackId();

}  // namespace meet_video_effects

#endif  // MEET_DESKTOP_WEBRTC_INTERNALS_H_
