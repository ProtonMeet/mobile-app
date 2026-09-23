/*
 * Copyright (c) 2026 Proton AG
 * Still-image decoding for desktop virtual backgrounds.
 */

#ifndef MEET_DESKTOP_IMAGE_DECODER_H_
#define MEET_DESKTOP_IMAGE_DECODER_H_

#include <cstdint>
#include <string>
#include <vector>

namespace meet_video_effects {

/** Tightly packed RGBA8888, row-major, width*height*4 bytes. */
struct DecodedImage {
  int width = 0;
  int height = 0;
  std::vector<uint8_t> rgba;

  bool valid() const {
    return width > 0 && height > 0 &&
           rgba.size() == static_cast<size_t>(width) * height * 4;
  }
};

/**
 * Decodes an image file (PNG/JPEG/…) into RGBA.
 *
 * EXIF orientation is applied so portrait photos are not sideways, matching
 * Android's applyExifOrientation. Returns an invalid image on failure; the
 * caller reports that as the "failed to decode" channel error.
 *
 * Implemented per platform: WIC under windows/, GdkPixbuf under linux/.
 */
DecodedImage DecodeImageFile(const std::string& path);

/** As [DecodeImageFile], for an in-memory encoded image (`imageBytes`). */
DecodedImage DecodeImageBytes(const uint8_t* data, size_t size);

}  // namespace meet_video_effects

#endif  // MEET_DESKTOP_IMAGE_DECODER_H_
