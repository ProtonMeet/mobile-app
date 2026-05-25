/*
 * Copyright (c) 2026 Proton AG
 * Desktop (Linux/Windows) method-channel backend for background blur.
 */

#ifndef MEET_DESKTOP_BACKGROUND_BLUR_H_
#define MEET_DESKTOP_BACKGROUND_BLUR_H_

#include <string>

namespace meet_video_effects {

struct DesktopMethodResult {
  bool success = true;
  bool bool_value = false;
  std::string error_code;
  std::string error_message;
};

class DesktopBackgroundBlur {
 public:
  static DesktopBackgroundBlur& Instance();

  DesktopMethodResult Handle(const std::string& method,
                             const std::string& track_id);

  /** Directory containing bundled .tflite models (set at plugin register). */
  void SetModelsDirectory(std::string path);

  bool IsReady() const;

 private:
  DesktopBackgroundBlur() = default;

  std::string models_dir_;
  std::string ResolveModelPath(const std::string& file_name) const;
};

}  // namespace meet_video_effects

#endif  // MEET_DESKTOP_BACKGROUND_BLUR_H_
