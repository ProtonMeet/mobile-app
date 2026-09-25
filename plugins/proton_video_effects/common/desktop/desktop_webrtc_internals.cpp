/*
 * Copyright (c) 2026 Proton AG
 */

#include "desktop_webrtc_internals.h"

#include "desktop_log.h"
#include "desktop_webrtc_instance.h"

#include <atomic>
#include <chrono>
#include <map>
#include <mutex>
#include <sstream>
#include <string>

#include "flutter_webrtc.h"
#include "rtc_mediaconstraints.h"
#include "rtc_video_frame.h"
#include "rtc_video_source.h"
#include "rtc_video_track.h"

namespace meet_video_effects {
namespace {

using flutter_webrtc_plugin::FlutterWebRTC;
using flutter_webrtc_plugin::FlutterWebRTCBase;
using libwebrtc::RTCMediaTrack;
using libwebrtc::RTCPeerConnectionFactory;
using libwebrtc::scoped_refptr;

/*
 * Reaching flutter_webrtc's protected members without modifying it.
 *
 * `instance->factory_` is rejected outright (MSVC C2248), and the plugin
 * library exports no C++ symbols, so there is no accessor to call either. The
 * way out is that an explicit template instantiation is allowed to name an
 * otherwise inaccessible member ([temp.spec]/6): instantiating Stealer below
 * defines a friend that hands back a pointer-to-member typed on the *base*
 * class, which ordinary code may then apply to any base object.
 *
 * This is the standard idiom for the problem. It is not a cast and does not
 * reinterpret the object — the member is found through a real pointer-to-member
 * with the correct type, so there is no undefined behaviour and no aliasing
 * trick. What it does rely on is FlutterWebRTCBase having the fields this
 * translation unit was compiled against, which is why:
 *
 *   - pubspec.yaml pins flutter_webrtc to an exact version rather than `^`, so
 *     the layout cannot shift under us on a routine `pub upgrade`, and
 *   - ProbeWebRtcInternals() sanity-checks the result at runtime before any
 *     caller depends on it.
 *
 * The alternative was patching flutter_webrtc to export a registration hook.
 * That is cleaner but means carrying a dependency patch on every machine and in
 * CI; see native/README.md for the comparison.
 */
template <typename Tag, typename Tag::type Member>
struct Stealer {
  friend typename Tag::type StolenMember(Tag) { return Member; }
};

struct FactoryTag {
  using type = scoped_refptr<RTCPeerConnectionFactory> FlutterWebRTCBase::*;
  friend type StolenMember(FactoryTag);
};
template struct Stealer<FactoryTag, &FlutterWebRTCBase::factory_>;

struct LocalTracksTag {
  using type =
      std::map<std::string, scoped_refptr<RTCMediaTrack>> FlutterWebRTCBase::*;
  friend type StolenMember(LocalTracksTag);
};
template struct Stealer<LocalTracksTag, &FlutterWebRTCBase::local_tracks_>;

// The custom source and the track wrapping it, alive between
// CreateProcessedVideoTrack and DestroyProcessedVideoTrack.
std::mutex g_track_mutex;
scoped_refptr<libwebrtc::RTCVideoSource> g_processed_source;
scoped_refptr<libwebrtc::RTCVideoTrack> g_processed_track;
std::string g_processed_track_id;

/**
 * A track id unique within this process.
 *
 * flutter_webrtc's own `GenerateUUID` is a non-virtual member and the plugin
 * library exports no C++ symbols, so it cannot be called from here. Dart treats
 * track ids as opaque, so any collision-free string works; the prefix makes the
 * origin obvious in logs and in flutter_webrtc's track map.
 */
std::string NewProcessedTrackId() {
  static std::atomic<uint64_t> counter{0};
  const auto now = std::chrono::steady_clock::now().time_since_epoch().count();
  std::ostringstream id;
  id << "proton-fx-" << now << "-"
     << counter.fetch_add(1, std::memory_order_relaxed);
  return id.str();
}

}  // namespace

WebRtcInternals ProbeWebRtcInternals() {
  WebRtcInternals out;
  FlutterWebRTC* instance = GetFlutterWebRtcSharedInstance();
  if (!instance) return out;
  out.instance_found = true;

  FlutterWebRTCBase* base = instance;

  // Public and virtual, so this needs no field offset. It is assigned in
  // EnsureWebRTCInitialized right after factory_, which makes it a reliable
  // "has the factory been constructed yet?" signal.
  out.webrtc_initialized = base->audio_processing() != nullptr;

  const auto& factory = base->*StolenMember(FactoryTag{});
  out.factory_found = factory != nullptr;

  const auto& local_tracks = base->*StolenMember(LocalTracksTag{});
  out.local_track_count = local_tracks.size();

  if (!out.webrtc_initialized) {
    // Nothing has been created yet; a null factory here says nothing either way.
    out.layout = WebRtcLayoutCheck::kInconclusive;
  } else if (out.factory_found) {
    out.layout = WebRtcLayoutCheck::kVerified;
  } else {
    out.layout = WebRtcLayoutCheck::kMismatch;
  }
  return out;
}

void LogWebRtcInternals(const char* context) {
  const WebRtcInternals p = ProbeWebRtcInternals();
  const char* layout = "inconclusive (flutter_webrtc not initialised yet)";
  if (p.layout == WebRtcLayoutCheck::kVerified) {
    layout = "verified";
  } else if (p.layout == WebRtcLayoutCheck::kMismatch) {
    layout = "MISMATCH — field offsets are wrong, do not publish through this";
  }
  MEET_VE_LOG() << context << ": webrtcInternals instanceFound="
                << (p.instance_found ? "true" : "false") << " webrtcInitialized="
                << (p.webrtc_initialized ? "true" : "false")
                << " factoryFound=" << (p.factory_found ? "true" : "false")
                << " localTrackCount=" << p.local_track_count
                << " layoutCheck=" << layout;
}

std::string CreateProcessedVideoTrack() {
  const WebRtcInternals probe = ProbeWebRtcInternals();
  if (probe.layout != WebRtcLayoutCheck::kVerified) {
    MEET_VE_LOG() << "createProcessedTrack: refusing, layout check is not "
                     "verified (webrtcInitialized="
                  << (probe.webrtc_initialized ? "true" : "false")
                  << " factoryFound="
                  << (probe.factory_found ? "true" : "false") << ")";
    return {};
  }

  std::lock_guard<std::mutex> lock(g_track_mutex);
  if (g_processed_track) return g_processed_track_id;

  FlutterWebRTCBase* base = GetFlutterWebRtcSharedInstance();
  const auto& factory = base->*StolenMember(FactoryTag{});

  auto constraints = libwebrtc::RTCMediaConstraints::Create();
  auto source = factory->CreateCustomVideoSource("proton-video-effects",
                                                 constraints);
  if (!source) {
    MEET_VE_LOG() << "createProcessedTrack: CreateCustomVideoSource returned "
                     "null";
    return {};
  }
  // A camera-backed source silently ignores OnCapturedFrame; only a custom one
  // accepts injection, so a wrong type here would fail invisibly later.
  if (source->GetSourceType() != libwebrtc::RTCVideoSource::SourceType::kCustom) {
    MEET_VE_LOG() << "createProcessedTrack: source is not kCustom, frames "
                     "would be dropped silently";
    return {};
  }

  const std::string id = NewProcessedTrackId();
  auto track = factory->CreateVideoTrack(source, id);
  if (!track) {
    MEET_VE_LOG() << "createProcessedTrack: CreateVideoTrack returned null";
    return {};
  }

  // Registering here is what lets Dart find the track: every flutter_webrtc
  // method channel call resolves ids through this map.
  auto& local_tracks = base->*StolenMember(LocalTracksTag{});
  local_tracks[id] = track;

  g_processed_source = source;
  g_processed_track = track;
  g_processed_track_id = id;
  MEET_VE_LOG() << "createProcessedTrack: id=" << id
                << " registered, localTrackCount=" << local_tracks.size();
  return id;
}

void PushProcessedFrame(int width, int height, const uint8_t* y, int stride_y,
                        const uint8_t* u, int stride_u, const uint8_t* v,
                        int stride_v) {
  scoped_refptr<libwebrtc::RTCVideoSource> source;
  {
    std::lock_guard<std::mutex> lock(g_track_mutex);
    source = g_processed_source;
  }
  if (!source || width <= 0 || height <= 0 || !y || !u || !v) return;

  // Create copies the planes, so the engine's reusable buffers are safe to
  // overwrite as soon as this returns.
  auto frame = libwebrtc::RTCVideoFrame::Create(width, height, y, stride_y, u,
                                                stride_u, v, stride_v);
  if (frame) source->OnCapturedFrame(frame);
}

void DestroyProcessedVideoTrack() {
  std::string id;
  {
    std::lock_guard<std::mutex> lock(g_track_mutex);
    if (!g_processed_track) return;
    id = g_processed_track_id;
    // Dropped before touching flutter_webrtc's map so a frame arriving on the
    // capture thread stops finding a source immediately.
    g_processed_source = nullptr;
    g_processed_track = nullptr;
    g_processed_track_id.clear();
  }

  FlutterWebRTCBase* base = GetFlutterWebRtcSharedInstance();
  if (base) {
    auto& local_tracks = base->*StolenMember(LocalTracksTag{});
    local_tracks.erase(id);
  }
  MEET_VE_LOG() << "destroyProcessedTrack: id=" << id << " removed";
}

std::string ProcessedVideoTrackId() {
  std::lock_guard<std::mutex> lock(g_track_mutex);
  return g_processed_track_id;
}

}  // namespace meet_video_effects
