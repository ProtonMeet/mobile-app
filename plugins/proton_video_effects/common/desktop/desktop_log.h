/*
 * Copyright (c) 2026 Proton AG
 * Diagnostic logging for the desktop (Linux/Windows) video-effects plugin.
 */

#ifndef MEET_DESKTOP_LOG_H_
#define MEET_DESKTOP_LOG_H_

#include <sstream>
#include <string>

namespace meet_video_effects {

/**
 * Writes one tagged line to stderr, which `flutter run` forwards to the
 * console. Uses the same "ProtonVideoEffects" tag as the Android and Apple
 * plugins so desktop logs can be filtered the same way.
 */
void LogLine(const std::string& message);

/** Accumulates a line and emits it on destruction; see [MEET_VE_LOG]. */
class LogStream {
 public:
  LogStream() = default;
  ~LogStream() { LogLine(buffer_.str()); }

  LogStream(const LogStream&) = delete;
  LogStream& operator=(const LogStream&) = delete;

  std::ostringstream& stream() { return buffer_; }

 private:
  std::ostringstream buffer_;
};

/** Usage: `MEET_VE_LOG() << "attach: trackId=" << id;` */
#define MEET_VE_LOG() ::meet_video_effects::LogStream().stream()

}  // namespace meet_video_effects

#endif  // MEET_DESKTOP_LOG_H_
