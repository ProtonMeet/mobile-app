/*
 * Copyright (c) 2026 Proton AG
 */

#include "desktop_log.h"

#include <iostream>
#include <mutex>

namespace meet_video_effects {
namespace {

// Frames arrive on the capture thread while channel calls arrive on the
// platform thread, so without this the two interleave mid-line.
std::mutex g_log_mutex;

}  // namespace

void LogLine(const std::string& message) {
  std::lock_guard<std::mutex> lock(g_log_mutex);
  std::cerr << "[ProtonVideoEffects] " << message << std::endl;
}

}  // namespace meet_video_effects
