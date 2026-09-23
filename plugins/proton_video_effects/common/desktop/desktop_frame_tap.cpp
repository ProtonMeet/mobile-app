/*
 * Copyright (c) 2026 Proton AG
 *
 * Only `virtual` members of flutter_webrtc / libwebrtc objects are used here.
 * flutter_webrtc's plugin library exports nothing but its two registration
 * symbols, so every call has to dispatch through a vtable — the same constraint
 * livekit_client's desktop plugin works within.
 */

#include "desktop_frame_tap.h"

#include "desktop_background_blur.h"
#include "desktop_log.h"
#include "desktop_webrtc_instance.h"
#include "desktop_webrtc_internals.h"

#include <atomic>
#include <map>
#include <memory>
#include <mutex>

#include "flutter_webrtc.h"
#include "rtc_media_track.h"
#include "rtc_video_frame.h"
#include "rtc_video_renderer.h"
#include "rtc_video_track.h"

namespace meet_video_effects {
namespace {

using libwebrtc::RTCVideoFrame;
using libwebrtc::RTCVideoTrack;
using libwebrtc::scoped_refptr;

std::atomic<int64_t> g_processed{0};
std::atomic<int64_t> g_passthrough{0};

// Roughly every 10 seconds at 30fps.
constexpr int64_t kLogEveryNFrames = 300;

/**
 * Receives frames from one video track.
 *
 * libwebrtc delivers to every sink of a source synchronously on the capture
 * thread, so OnFrame runs on that thread and must not block: anything slower
 * than inference belongs elsewhere.
 */
class TrackFrameSink : public libwebrtc::RTCVideoRenderer<scoped_refptr<RTCVideoFrame>> {
 public:
  explicit TrackFrameSink(scoped_refptr<RTCVideoTrack> track)
      : track_(track) {}

  ~TrackFrameSink() override { Detach(); }

  void Attach() {
    if (attached_ || !track_) return;
    track_->AddRenderer(this);
    attached_ = true;
  }

  void Detach() {
    if (!attached_ || !track_) return;
    // Must happen before this object dies: the track would otherwise keep
    // calling into freed memory from the capture thread.
    track_->RemoveRenderer(this);
    attached_ = false;
  }

  void OnFrame(scoped_refptr<RTCVideoFrame> frame) override {
    if (!frame) return;

    ProcessedI420 processed;
    const bool ok = DesktopBackgroundBlur::Instance().ProcessI420(
        frame->width(), frame->height(), static_cast<int>(frame->rotation()),
        frame->DataY(), frame->StrideY(), frame->DataU(), frame->StrideU(),
        frame->DataV(), frame->StrideV(), &processed);

    // First frame proves the tap is live; the periodic line then shows it is
    // still running without flooding the console at 30fps.
    if (!ok) {
      const int64_t n = g_passthrough.fetch_add(1, std::memory_order_relaxed) + 1;
      if (n == 1 || n % kLogEveryNFrames == 0) {
        MEET_VE_LOG() << "frameTap: " << n << " frame(s) passed through "
                      << "unprocessed (engine declined or not ready), latest "
                      << frame->width() << "x" << frame->height();
      }
      // The processed track is published for the whole call, so it must carry
      // the camera even with no effect active: skipping this push would send
      // black video whenever the engine declines a frame.
      PushProcessedFrame(frame->width(), frame->height(), frame->DataY(),
                         frame->StrideY(), frame->DataU(), frame->StrideU(),
                         frame->DataV(), frame->StrideV());
      return;
    }
    const int64_t n = g_processed.fetch_add(1, std::memory_order_relaxed) + 1;
    if (n == 1 || n % kLogEveryNFrames == 0) {
      MEET_VE_LOG() << "frameTap: " << n << " frame(s) processed, latest "
                    << frame->width() << "x" << frame->height() << " -> "
                    << processed.width << "x" << processed.height;
    }

    // Into the custom source, which broadcasts to every sink subscribed to it
    // — including the RTP encoder once Dart publishes the processed track.
    PushProcessedFrame(processed.width, processed.height, processed.y,
                       processed.stride_y, processed.u, processed.stride_u,
                       processed.v, processed.stride_v);
  }

 private:
  scoped_refptr<RTCVideoTrack> track_;
  bool attached_ = false;
};

std::mutex g_mutex;
std::map<std::string, std::unique_ptr<TrackFrameSink>> g_sinks;

/** Resolves a track id to a live video track, or nullptr. */
scoped_refptr<RTCVideoTrack> VideoTrackForId(const std::string& track_id) {
  if (track_id.empty()) {
    MEET_VE_LOG() << "frameTap: empty trackId";
    return nullptr;
  }
  flutter_webrtc_plugin::FlutterWebRTC* webrtc = GetFlutterWebRtcSharedInstance();
  if (!webrtc) {
    MEET_VE_LOG() << "frameTap: flutter_webrtc shared instance not available "
                     "(plugin not loaded, or the accessor was not found)";
    return nullptr;
  }

  // MediaTrackForId is virtual, so it dispatches without linking.
  scoped_refptr<libwebrtc::RTCMediaTrack> track = webrtc->MediaTrackForId(track_id);
  if (!track) {
    MEET_VE_LOG() << "frameTap: no track registered for id='" << track_id
                  << "'";
    return nullptr;
  }
  const std::string kind = track->kind().std_string();
  if (kind != "video") {
    MEET_VE_LOG() << "frameTap: track id='" << track_id << "' is kind='" << kind
                  << "', expected video";
    return nullptr;
  }

  // Same downcast livekit_client performs for audio tracks; the kind check
  // above is what makes it safe.
  return scoped_refptr<RTCVideoTrack>(
      static_cast<RTCVideoTrack*>(track.get()));
}

}  // namespace

DesktopFrameTap& DesktopFrameTap::Instance() {
  static DesktopFrameTap instance;
  return instance;
}

bool DesktopFrameTap::Start(const std::string& track_id) {
  scoped_refptr<RTCVideoTrack> track = VideoTrackForId(track_id);
  if (!track) return false;

  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_sinks.find(track_id) != g_sinks.end()) return true;

  auto sink = std::make_unique<TrackFrameSink>(track);
  sink->Attach();
  g_sinks.emplace(track_id, std::move(sink));
  return true;
}

void DesktopFrameTap::Stop(const std::string& track_id) {
  std::unique_ptr<TrackFrameSink> sink;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    auto it = g_sinks.find(track_id);
    if (it == g_sinks.end()) return;
    sink = std::move(it->second);
    g_sinks.erase(it);
  }
  // Destroyed outside the lock: RemoveRenderer blocks until the capture thread
  // is done with this sink, and that thread may be inside OnFrame waiting on
  // the engine.
  sink.reset();
}

void DesktopFrameTap::StopAll() {
  std::map<std::string, std::unique_ptr<TrackFrameSink>> sinks;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    sinks.swap(g_sinks);
  }
  sinks.clear();
}

int64_t DesktopFrameTap::processed_frames() const {
  return g_processed.load(std::memory_order_relaxed);
}

int64_t DesktopFrameTap::passthrough_frames() const {
  return g_passthrough.load(std::memory_order_relaxed);
}

}  // namespace meet_video_effects
