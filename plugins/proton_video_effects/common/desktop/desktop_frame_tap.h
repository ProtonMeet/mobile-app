/*
 * Copyright (c) 2026 Proton AG
 * Taps camera frames off a flutter_webrtc video track and runs them through the
 * background-effects engine.
 */

#ifndef MEET_DESKTOP_FRAME_TAP_H_
#define MEET_DESKTOP_FRAME_TAP_H_

#include <cstdint>
#include <string>

namespace meet_video_effects {

/**
 * Observes a local camera track and segments every frame.
 *
 * flutter_webrtc exposes no way to put a frame *back* into a track's source on
 * desktop (see native/README.md), so this only reads: the processed result is
 * handed to whatever consumer is registered, and the frames the encoder sends
 * are still the raw camera frames. It is the shared half of the eventual
 * pipeline, and on its own it backs a locally processed self-view.
 *
 * Deliberately kept free of libwebrtc types: they leak a large header tree and
 * are confined to desktop_frame_tap.cpp.
 */
class DesktopFrameTap {
 public:
  static DesktopFrameTap& Instance();

  /**
   * Starts observing [track_id].
   *
   * Returns false when flutter_webrtc is unavailable or the id is not a live
   * video track. Starting an already-tapped track is a no-op that succeeds.
   */
  bool Start(const std::string& track_id);

  /** Stops observing [track_id]; unknown ids are ignored. */
  void Stop(const std::string& track_id);

  /** Detaches every tap. Safe to call when nothing is attached. */
  void StopAll();

  /** Frames successfully segmented since process start; for diagnostics. */
  int64_t processed_frames() const;

  /** Frames seen but passed through unchanged (engine declined or not ready). */
  int64_t passthrough_frames() const;

 private:
  DesktopFrameTap() = default;
  ~DesktopFrameTap() = default;
  DesktopFrameTap(const DesktopFrameTap&) = delete;
  DesktopFrameTap& operator=(const DesktopFrameTap&) = delete;
};

}  // namespace meet_video_effects

#endif  // MEET_DESKTOP_FRAME_TAP_H_
