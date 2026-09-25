/*
 * Copyright (c) 2026 Proton AG
 * Linux implementation of the shared image decoder, backed by GdkPixbuf.
 * The interface and every caller live in common/desktop.
 */

#include <gdk-pixbuf/gdk-pixbuf.h>

#include "desktop_image_decoder.h"

namespace meet_video_effects {
namespace {

/** Normalises to tightly packed RGBA; GdkPixbuf may be RGB or row-padded. */
DecodedImage FromPixbuf(GdkPixbuf* pixbuf) {
  DecodedImage image;
  if (!pixbuf) return image;

  // Honours the EXIF tag when present; returns a new ref either way.
  GdkPixbuf* oriented = gdk_pixbuf_apply_embedded_orientation(pixbuf);
  GdkPixbuf* source = oriented ? oriented : pixbuf;

  const int width = gdk_pixbuf_get_width(source);
  const int height = gdk_pixbuf_get_height(source);
  const int channels = gdk_pixbuf_get_n_channels(source);
  const int stride = gdk_pixbuf_get_rowstride(source);
  const guchar* pixels = gdk_pixbuf_get_pixels(source);

  if (width > 0 && height > 0 && (channels == 3 || channels == 4) && pixels) {
    image.width = width;
    image.height = height;
    image.rgba.resize(static_cast<size_t>(width) * height * 4);
    for (int y = 0; y < height; ++y) {
      const guchar* src_row = pixels + static_cast<size_t>(y) * stride;
      uint8_t* dst_row = image.rgba.data() + static_cast<size_t>(y) * width * 4;
      for (int x = 0; x < width; ++x) {
        const guchar* src = src_row + static_cast<size_t>(x) * channels;
        uint8_t* dst = dst_row + static_cast<size_t>(x) * 4;
        dst[0] = src[0];
        dst[1] = src[1];
        dst[2] = src[2];
        dst[3] = channels == 4 ? src[3] : 0xFF;
      }
    }
  }

  if (oriented) g_object_unref(oriented);
  return image;
}

}  // namespace

DecodedImage DecodeImageFile(const std::string& path) {
  if (path.empty()) return {};
  GError* error = nullptr;
  GdkPixbuf* pixbuf = gdk_pixbuf_new_from_file(path.c_str(), &error);
  if (error) g_error_free(error);
  DecodedImage image = FromPixbuf(pixbuf);
  if (pixbuf) g_object_unref(pixbuf);
  return image;
}

DecodedImage DecodeImageBytes(const uint8_t* data, size_t size) {
  if (!data || size == 0) return {};
  GdkPixbufLoader* loader = gdk_pixbuf_loader_new();
  if (!loader) return {};

  DecodedImage image;
  GError* error = nullptr;
  const gboolean written = gdk_pixbuf_loader_write(loader, data, size, &error);
  if (error) {
    g_error_free(error);
    error = nullptr;
  }
  // The loader must be closed exactly once, including after a failed write.
  const gboolean closed = gdk_pixbuf_loader_close(loader, &error);
  if (error) g_error_free(error);

  if (written && closed) {
    // Transfer-none: the loader owns this pixbuf, so it is not unreffed here.
    image = FromPixbuf(gdk_pixbuf_loader_get_pixbuf(loader));
  }
  g_object_unref(loader);
  return image;
}

}  // namespace meet_video_effects
