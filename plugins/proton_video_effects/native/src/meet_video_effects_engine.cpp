/*
 * Copyright (c) 2026 Proton AG
 * TensorFlow Lite selfie segmentation + CPU background blur for Linux/Windows.
 */

#include "meet_video_effects.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <memory>
#include <mutex>
#include <vector>

#ifdef MEET_VIDEO_EFFECTS_USE_TFLITE
#include "meet_video_effects_custom_ops.h"
#include "tensorflow/lite/c/c_api.h"
#endif

namespace {

constexpr int kSegmenterSize = 256;
// Frames are composited at their own size up to this long side, so a 720p
// camera now round-trips unscaled. Segmentation is unaffected either way: the
// mask is always inferred at kSegmenterSize, so only the colour conversions and
// the composite scale with this, and the blur plate stays cheap via
// kBlurDownsample. Lower it if compositing cannot keep up with the capture
// rate; 1080p still downscales to 1280x720.
constexpr int kProcessingLongSide = 1280;
constexpr float kBlurDownsample = 0.25f;
constexpr int kBlurRadius = 8;

// Floor for the feather sigma, in mask pixels. The bundled segmenter emits a
// confidence mask, so most of the smoothness comes from the source and this
// only guarantees the upscale has about a pixel of ramp to interpolate. Matches
// MASK_FEATHER_SIGMA_MIN_CONFIDENCE on Android.
constexpr float kMaskFeatherSigmaFloor = 0.9f;

// Mask shaping defaults mirror Dart's MaskEdgeTuning; keep the two in sync.
constexpr float kDefaultFeatherHeightFraction = 0.010f;
constexpr float kDefaultErodeHeightFraction = 0.002f;
constexpr float kDefaultSolidifySlope = 6.f;
constexpr float kDefaultSolidifyMidpoint = 0.55f;
constexpr float kDefaultForegroundGamma = 1.f;

// Blur tunables mirror BackgroundBlurConfig / the Android engine so the same
// slider produces a comparable result on every platform.
constexpr float kDefaultBlurSigma = 128.f;
constexpr float kDefaultObscureOpacity = 0.1f;

// Desaturate the blurred camera plate (0 = full colour, 1 = grey).
// Matches Android BACKGROUND_DESATURATION and iOS backgroundDesaturation.
constexpr float kBackgroundDesaturation = 0.5f;

// Veil tint over the blurred plate; same neutral grey as Android.
constexpr int kVeilR = 115;
constexpr int kVeilG = 115;
constexpr int kVeilB = 122;

struct I420Buffer {
  int width = 0;
  int height = 0;
  std::vector<uint8_t> y;
  std::vector<uint8_t> u;
  std::vector<uint8_t> v;
  int stride_y = 0;
  int stride_u = 0;
  int stride_v = 0;
};

static int Even(int v) { return (v / 2) * 2; }

static void ComputeTargetSize(int src_w, int src_h, int cap, int* out_w, int* out_h) {
  if (cap <= 0 || std::max(src_w, src_h) <= cap) {
    *out_w = Even(src_w);
    *out_h = Even(src_h);
    return;
  }
  const float s = static_cast<float>(cap) / static_cast<float>(std::max(src_w, src_h));
  *out_w = Even(static_cast<int>(src_w * s));
  *out_h = Even(static_cast<int>(src_h * s));
}

static void I420ToArgb(
    const I420Buffer& i420, std::vector<uint32_t>* argb) {
  const int w = i420.width;
  const int h = i420.height;
  argb->resize(static_cast<size_t>(w * h));
  for (int y = 0; y < h; ++y) {
    for (int x = 0; x < w; ++x) {
      const int yv = static_cast<int>(i420.y[y * i420.stride_y + x]) - 16;
      const int uv = static_cast<int>(i420.u[(y / 2) * i420.stride_u + (x / 2)]) - 128;
      const int vv = static_cast<int>(i420.v[(y / 2) * i420.stride_v + (x / 2)]) - 128;
      const int c298 = 298 * yv;
      const int r = (c298 + 409 * vv + 128) >> 8;
      const int g = (c298 - 100 * uv - 208 * vv + 128) >> 8;
      const int b = (c298 + 516 * uv + 128) >> 8;
      (*argb)[y * w + x] =
          0xFF000000u |
          (static_cast<uint32_t>(std::clamp(r, 0, 255)) << 16) |
          (static_cast<uint32_t>(std::clamp(g, 0, 255)) << 8) |
          static_cast<uint32_t>(std::clamp(b, 0, 255));
    }
  }
}

static void ArgbToI420(
    const std::vector<uint32_t>& argb, int w, int h, I420Buffer* out) {
  out->width = w;
  out->height = h;
  out->stride_y = w;
  out->stride_u = w / 2;
  out->stride_v = w / 2;
  out->y.resize(static_cast<size_t>(w * h));
  out->u.resize(static_cast<size_t>((w / 2) * (h / 2)));
  out->v.resize(static_cast<size_t>((w / 2) * (h / 2)));
  for (int y = 0; y < h; ++y) {
    for (int x = 0; x < w; ++x) {
      const uint32_t px = argb[y * w + x];
      const int r = (px >> 16) & 0xFF;
      const int g = (px >> 8) & 0xFF;
      const int b = px & 0xFF;
      const int yv = ((66 * r + 129 * g + 25 * b + 128) >> 8) + 16;
      out->y[y * w + x] = static_cast<uint8_t>(std::clamp(yv, 0, 255));
    }
  }
  for (int y = 0; y < h; y += 2) {
    for (int x = 0; x < w; x += 2) {
      const uint32_t px = argb[y * w + x];
      const int r = (px >> 16) & 0xFF;
      const int g = (px >> 8) & 0xFF;
      const int b = px & 0xFF;
      const int uv = ((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128;
      const int vv = ((112 * r - 94 * g - 18 * b + 128) >> 8) + 128;
      out->u[(y / 2) * out->stride_u + (x / 2)] =
          static_cast<uint8_t>(std::clamp(uv, 0, 255));
      out->v[(y / 2) * out->stride_v + (x / 2)] =
          static_cast<uint8_t>(std::clamp(vv, 0, 255));
    }
  }
}

static void BoxBlurArgb(std::vector<uint32_t>* pixels, int w, int h, int radius) {
  if (radius < 1) return;
  const int div = radius * 2 + 1;
  std::vector<uint32_t> tmp(pixels->size());
  for (int y = 0; y < h; ++y) {
    int r_sum = 0, g_sum = 0, b_sum = 0;
    for (int k = -radius; k <= radius; ++k) {
      const int xx = std::clamp(k, 0, w - 1);
      const uint32_t px = (*pixels)[y * w + xx];
      r_sum += (px >> 16) & 0xFF;
      g_sum += (px >> 8) & 0xFF;
      b_sum += px & 0xFF;
    }
    for (int x = 0; x < w; ++x) {
      tmp[y * w + x] = 0xFF000000u | ((r_sum / div) << 16) | ((g_sum / div) << 8) |
                       (b_sum / div);
      const int x_out = std::clamp(x - radius, 0, w - 1);
      const int x_in = std::clamp(x + radius + 1, 0, w - 1);
      const uint32_t px_out = (*pixels)[y * w + x_out];
      const uint32_t px_in = (*pixels)[y * w + x_in];
      r_sum += ((px_in >> 16) & 0xFF) - ((px_out >> 16) & 0xFF);
      g_sum += ((px_in >> 8) & 0xFF) - ((px_out >> 8) & 0xFF);
      b_sum += (px_in & 0xFF) - (px_out & 0xFF);
    }
  }
  for (int x = 0; x < w; ++x) {
    int r_sum = 0, g_sum = 0, b_sum = 0;
    for (int k = -radius; k <= radius; ++k) {
      const int yy = std::clamp(k, 0, h - 1);
      const uint32_t px = tmp[yy * w + x];
      r_sum += (px >> 16) & 0xFF;
      g_sum += (px >> 8) & 0xFF;
      b_sum += px & 0xFF;
    }
    for (int y = 0; y < h; ++y) {
      (*pixels)[y * w + x] = 0xFF000000u | ((r_sum / div) << 16) | ((g_sum / div) << 8) |
                             (b_sum / div);
      const int y_out = std::clamp(y - radius, 0, h - 1);
      const int y_in = std::clamp(y + radius + 1, 0, h - 1);
      const uint32_t px_out = tmp[y_out * w + x];
      const uint32_t px_in = tmp[y_in * w + x];
      r_sum += ((px_in >> 16) & 0xFF) - ((px_out >> 16) & 0xFF);
      g_sum += ((px_in >> 8) & 0xFF) - ((px_out >> 8) & 0xFF);
      b_sum += (px_in & 0xFF) - (px_out & 0xFF);
    }
  }
}

static void FeatherMask(std::vector<uint8_t>* mask, int w, int h, float sigma) {
  if (sigma <= 0.f) return;
  const int radius = std::clamp(static_cast<int>(sigma * 3.f + 0.5f), 1, 12);
  std::vector<float> kernel(radius * 2 + 1);
  float sum = 0.f;
  for (int i = -radius; i <= radius; ++i) {
    const float v = std::exp(-(i * i) / (2.f * sigma * sigma));
    kernel[i + radius] = v;
    sum += v;
  }
  for (float& k : kernel) k /= sum;
  std::vector<uint8_t> pass1(mask->size());
  for (int y = 0; y < h; ++y) {
    for (int x = 0; x < w; ++x) {
      float acc = 0.f;
      for (int k = -radius; k <= radius; ++k) {
        const int xx = std::clamp(x + k, 0, w - 1);
        acc += (*mask)[y * w + xx] * kernel[k + radius];
      }
      pass1[y * w + x] = static_cast<uint8_t>(std::clamp(static_cast<int>(acc), 0, 255));
    }
  }
  for (int x = 0; x < w; ++x) {
    for (int y = 0; y < h; ++y) {
      float acc = 0.f;
      for (int k = -radius; k <= radius; ++k) {
        const int yy = std::clamp(y + k, 0, h - 1);
        acc += pass1[yy * w + x] * kernel[k + radius];
      }
      (*mask)[y * w + x] = static_cast<uint8_t>(std::clamp(static_cast<int>(acc), 0, 255));
    }
  }
}

// Shape of the mask before blending, as pushed by
// meet_video_effects_set_mask_edge_tuning. Stored clamped.
struct MaskEdgeTuning {
  float feather_height_fraction = kDefaultFeatherHeightFraction;
  float erode_height_fraction = kDefaultErodeHeightFraction;
  float solidify_slope = kDefaultSolidifySlope;
  float solidify_midpoint = kDefaultSolidifyMidpoint;
  float foreground_gamma = kDefaultForegroundGamma;

  bool operator==(const MaskEdgeTuning& other) const {
    return feather_height_fraction == other.feather_height_fraction &&
           erode_height_fraction == other.erode_height_fraction &&
           solidify_slope == other.solidify_slope &&
           solidify_midpoint == other.solidify_midpoint &&
           foreground_gamma == other.foreground_gamma;
  }
};

/**
 * Separable minimum filter — the counterpart of CIMorphologyMinimum on Apple
 * and erodeMask on Android.
 *
 * Erosion by a square structuring element is separable, so this is two
 * O(w*h*radius) passes rather than a 2-D window. Radii under half a pixel are
 * dropped, leaving the mask untouched.
 */
static void ErodeMask(std::vector<uint8_t>* mask, int w, int h, float radius) {
  const int r = static_cast<int>(radius + 0.5f);
  if (r < 1) return;
  std::vector<uint8_t> pass1(mask->size());
  for (int y = 0; y < h; ++y) {
    const int row = y * w;
    for (int x = 0; x < w; ++x) {
      uint8_t m = 255;
      for (int k = -r; k <= r; ++k) {
        m = std::min(m, (*mask)[row + std::clamp(x + k, 0, w - 1)]);
      }
      pass1[row + x] = m;
    }
  }
  for (int x = 0; x < w; ++x) {
    for (int y = 0; y < h; ++y) {
      uint8_t m = 255;
      for (int k = -r; k <= r; ++k) {
        m = std::min(m, pass1[std::clamp(y + k, 0, h - 1) * w + x]);
      }
      (*mask)[y * w + x] = m;
    }
  }
}

/**
 * Builds the 256-entry table for one of the per-sample tone stages.
 *
 * Both solidify and gamma are pure functions of the alpha byte, so evaluating
 * them per mask pixel — 65 536 powf calls a frame for gamma alone — is wasted
 * work on the capture thread.
 */
static void BuildSolidifyLut(const MaskEdgeTuning& edge, uint8_t lut[256]) {
  // Same linear stretch about the midpoint that Apple runs as a CIColorMatrix,
  // clamped for the same reason: the stretch pushes values past 0 and 1, and an
  // out-of-range alpha would survive into the blend.
  const float bias = 0.5f - edge.solidify_slope * edge.solidify_midpoint;
  for (int i = 0; i < 256; ++i) {
    const float v = edge.solidify_slope > 1.f
                        ? edge.solidify_slope * (i / 255.f) + bias
                        : i / 255.f;
    lut[i] = static_cast<uint8_t>(
        std::clamp(static_cast<int>(v * 255.f), 0, 255));
  }
}

static void BuildGammaLut(const MaskEdgeTuning& edge, uint8_t lut[256]) {
  for (int i = 0; i < 256; ++i) {
    const float v = std::pow(i / 255.f, edge.foreground_gamma);
    lut[i] = static_cast<uint8_t>(
        std::clamp(static_cast<int>(v * 255.f), 0, 255));
  }
}

static void ApplyLut(std::vector<uint8_t>* mask, const uint8_t lut[256]) {
  for (uint8_t& v : *mask) v = lut[v];
}

#ifdef MEET_VIDEO_EFFECTS_USE_TFLITE
struct TfliteSegmenter {
  TfLiteModel* model = nullptr;
  TfLiteInterpreter* interpreter = nullptr;
  bool multiclass = false;

  bool Load(const char* path) {
    model = TfLiteModelCreateFromFile(path);
    if (!model) return false;
    TfLiteInterpreterOptions* options = TfLiteInterpreterOptionsCreate();
    TfLiteInterpreterOptionsSetNumThreads(options, 2);
    // The bundled MediaPipe models use a custom operator that stock TFLite does
    // not ship; without this the interpreter fails to build.
    meet_video_effects::RegisterCustomOps(options);
    interpreter = TfLiteInterpreterCreate(model, options);
    TfLiteInterpreterOptionsDelete(options);
    if (!interpreter) {
      TfLiteModelDelete(model);
      model = nullptr;
      return false;
    }
    if (TfLiteInterpreterAllocateTensors(interpreter) != kTfLiteOk) {
      TfLiteModelDelete(model);
      TfLiteInterpreterDelete(interpreter);
      model = nullptr;
      interpreter = nullptr;
      return false;
    }
    multiclass = std::strstr(path, "multiclass") != nullptr;
    return true;
  }

  ~TfliteSegmenter() {
    if (interpreter) TfLiteInterpreterDelete(interpreter);
    if (model) TfLiteModelDelete(model);
  }

  std::vector<uint8_t> Segment(const std::vector<uint32_t>& argb256) {
    TfLiteTensor* input = TfLiteInterpreterGetInputTensor(interpreter, 0);
    const int n = kSegmenterSize * kSegmenterSize;
    if (TfLiteTensorType(input) == kTfLiteFloat32) {
      float* in = static_cast<float*>(TfLiteTensorData(input));
      for (int i = 0; i < n; ++i) {
        const uint32_t px = argb256[i];
        in[i * 3 + 0] = ((px >> 16) & 0xFF) / 255.f;
        in[i * 3 + 1] = ((px >> 8) & 0xFF) / 255.f;
        in[i * 3 + 2] = (px & 0xFF) / 255.f;
      }
    }
    TfLiteInterpreterInvoke(interpreter);
    const TfLiteTensor* output = TfLiteInterpreterGetOutputTensor(interpreter, 0);
    std::vector<uint8_t> alpha(n);
    if (TfLiteTensorType(output) == kTfLiteFloat32) {
      const float* out = static_cast<const float*>(TfLiteTensorData(output));
      for (int i = 0; i < n; ++i) {
        float p = multiclass ? (1.f - out[i]) : out[i];
        alpha[i] = static_cast<uint8_t>(std::clamp(static_cast<int>(p * 255.f + 0.5f), 0, 255));
      }
    }
    return alpha;
  }
};
#endif

struct MeetVideoEffectsEngineImpl {
  std::mutex mutex;
#ifdef MEET_VIDEO_EFFECTS_USE_TFLITE
  std::unique_ptr<TfliteSegmenter> segmenter;
#endif
  std::vector<uint8_t> mask_small;
  std::vector<uint8_t> mask_full;
  std::vector<uint32_t> argb_work;
  /**
   * Composited result of the most recent frame, kept so a preview can read it
   * without re-running the pipeline. Same 0xAARRGGBB packing as [argb_work].
   */
  std::vector<uint32_t> last_composed;
  int last_composed_width = 0;
  int last_composed_height = 0;
  std::vector<uint32_t> blurred_work;
  I420Buffer output_i420;
  bool ready = false;

  int background_mode = kMeetVideoEffectsBackgroundBlur;
  float blur_sigma = kDefaultBlurSigma;
  float obscure_opacity = kDefaultObscureOpacity;

  MaskEdgeTuning mask_edge;
  // Tone tables for [mask_edge], rebuilt only when the tuning they were derived
  // from stops matching.
  uint8_t solidify_lut[256];
  uint8_t gamma_lut[256];
  bool tone_luts_valid = false;
  MaskEdgeTuning tone_lut_edge;

  void EnsureToneLuts() {
    if (tone_luts_valid && tone_lut_edge == mask_edge) return;
    BuildSolidifyLut(mask_edge, solidify_lut);
    BuildGammaLut(mask_edge, gamma_lut);
    tone_lut_edge = mask_edge;
    tone_luts_valid = true;
  }

  // Source pixels as handed over by the platform decoder.
  std::vector<uint32_t> replacement_argb;
  int replacement_width = 0;
  int replacement_height = 0;

  // Cover-scaled copy for the current frame size. Rebuilding it per frame would
  // resample the whole image on the capture thread for pixels that never change.
  std::vector<uint32_t> replacement_plate;
  int replacement_plate_width = 0;
  int replacement_plate_height = 0;

  bool UsesReplacementImage() const {
    return background_mode == kMeetVideoEffectsBackgroundImage &&
           replacement_width > 0 && replacement_height > 0;
  }

  void InvalidateReplacementPlate() {
    replacement_plate.clear();
    replacement_plate_width = 0;
    replacement_plate_height = 0;
  }
};

}  // namespace

struct MeetVideoEffectsEngine {
  MeetVideoEffectsEngineImpl impl;
};

MeetVideoEffectsEngine* meet_video_effects_create(const char* model_path) {
  if (!model_path || !*model_path) return nullptr;
  auto engine = std::make_unique<MeetVideoEffectsEngine>();
#ifdef MEET_VIDEO_EFFECTS_USE_TFLITE
  engine->impl.segmenter = std::make_unique<TfliteSegmenter>();
  engine->impl.ready = engine->impl.segmenter->Load(model_path);
#else
  (void)model_path;
  engine->impl.ready = false;
#endif
  if (!engine->impl.ready) {
    return nullptr;
  }
  return engine.release();
}

void meet_video_effects_destroy(MeetVideoEffectsEngine* engine) {
  if (!engine) return;
  // RAII teardown; pairs with std::make_unique in meet_video_effects_create.
  std::unique_ptr<MeetVideoEffectsEngine> owned(engine);
}

bool meet_video_effects_is_ready(const MeetVideoEffectsEngine* engine) {
  return engine && engine->impl.ready;
}

void meet_video_effects_set_background_mode(
    MeetVideoEffectsEngine* engine,
    MeetVideoEffectsBackgroundMode mode) {
  if (!engine) return;
  std::lock_guard<std::mutex> lock(engine->impl.mutex);
  engine->impl.background_mode = mode;
}

void meet_video_effects_set_blur_config(MeetVideoEffectsEngine* engine,
                                        float blur_sigma,
                                        float background_obscure_opacity) {
  if (!engine) return;
  std::lock_guard<std::mutex> lock(engine->impl.mutex);
  engine->impl.blur_sigma = std::clamp(blur_sigma, 4.f, 256.f);
  engine->impl.obscure_opacity = std::clamp(background_obscure_opacity, 0.f, 1.f);
}

void meet_video_effects_set_mask_edge_tuning(MeetVideoEffectsEngine* engine,
                                             float feather_height_fraction,
                                             float erode_height_fraction,
                                             float solidify_slope,
                                             float solidify_midpoint,
                                             float foreground_gamma) {
  if (!engine) return;
  std::lock_guard<std::mutex> lock(engine->impl.mutex);
  MaskEdgeTuning edge;
  edge.feather_height_fraction = std::clamp(feather_height_fraction, 0.f, 0.05f);
  edge.erode_height_fraction = std::clamp(erode_height_fraction, 0.f, 0.05f);
  edge.solidify_slope = std::clamp(solidify_slope, 1.f, 16.f);
  edge.solidify_midpoint = std::clamp(solidify_midpoint, 0.2f, 0.8f);
  edge.foreground_gamma = std::clamp(foreground_gamma, 0.5f, 3.f);
  engine->impl.mask_edge = edge;
}

bool meet_video_effects_set_replacement_image(MeetVideoEffectsEngine* engine,
                                              const uint8_t* rgba,
                                              int width,
                                              int height) {
  if (!engine) return false;
  std::lock_guard<std::mutex> lock(engine->impl.mutex);

  if (!rgba || width <= 0 || height <= 0) {
    engine->impl.replacement_argb.clear();
    engine->impl.replacement_width = 0;
    engine->impl.replacement_height = 0;
    engine->impl.InvalidateReplacementPlate();
    // Clearing is a valid request, not a decode failure.
    return rgba == nullptr;
  }

  const size_t count = static_cast<size_t>(width) * height;
  engine->impl.replacement_argb.resize(count);
  for (size_t i = 0; i < count; ++i) {
    const uint8_t* px = rgba + i * 4;
    engine->impl.replacement_argb[i] = 0xFF000000u |
                                       (static_cast<uint32_t>(px[0]) << 16) |
                                       (static_cast<uint32_t>(px[1]) << 8) |
                                       static_cast<uint32_t>(px[2]);
  }
  engine->impl.replacement_width = width;
  engine->impl.replacement_height = height;
  engine->impl.InvalidateReplacementPlate();
  return true;
}

static void ResizeArgbNearest(
    const std::vector<uint32_t>& src, int sw, int sh,
    std::vector<uint32_t>* dst, int dw, int dh) {
  dst->resize(static_cast<size_t>(dw * dh));
  for (int y = 0; y < dh; ++y) {
    const int sy = y * sh / dh;
    for (int x = 0; x < dw; ++x) {
      const int sx = x * sw / dw;
      (*dst)[y * dw + x] = src[sy * sw + sx];
    }
  }
}

/**
 * Aspect-fill: scales to cover the destination and centre-crops the overflow,
 * so a still background is never stretched. Mirrors Android scaleBitmapCover.
 */
static void ResizeArgbCover(
    const std::vector<uint32_t>& src, int sw, int sh,
    std::vector<uint32_t>* dst, int dw, int dh) {
  dst->assign(static_cast<size_t>(dw) * dh, 0xFF000000u);
  if (sw <= 0 || sh <= 0) return;
  const float scale = std::max(static_cast<float>(dw) / sw,
                               static_cast<float>(dh) / sh);
  const float off_x = (sw * scale - dw) * 0.5f;
  const float off_y = (sh * scale - dh) * 0.5f;
  for (int y = 0; y < dh; ++y) {
    const int sy = std::clamp(static_cast<int>((y + off_y) / scale), 0, sh - 1);
    for (int x = 0; x < dw; ++x) {
      const int sx = std::clamp(static_cast<int>((x + off_x) / scale), 0, sw - 1);
      (*dst)[static_cast<size_t>(y) * dw + x] = src[static_cast<size_t>(sy) * sw + sx];
    }
  }
}

/** Blur radius tracks the configured sigma, as on Android. */
static int BlurRadiusForSigma(float sigma) {
  const int radius =
      static_cast<int>(sigma / kDefaultBlurSigma * kBlurRadius);
  return std::clamp(radius, 1, 96);
}

/**
 * Mutes the real room behind the caller. Applied to the blurred camera plate
 * only — a replacement image is something the user picked, so tinting it would
 * just wash it out (same rule as Android BackgroundPlate.wantsObscureVeil).
 */
static void ApplyObscureVeil(std::vector<uint32_t>* plate, float opacity) {
  const int veil = std::clamp(static_cast<int>(opacity * 255.f + 0.5f), 0, 255);
  const int desat = std::clamp(
      static_cast<int>(kBackgroundDesaturation * 255.f + 0.5f), 0, 255);
  if (veil == 0 && desat == 0) return;
  for (uint32_t& px : *plate) {
    int r = (px >> 16) & 0xFF;
    int g = (px >> 8) & 0xFF;
    int b = px & 0xFF;
    if (desat > 0) {
      const int luma = (77 * r + 150 * g + 29 * b) >> 8;
      r += ((luma - r) * desat) / 255;
      g += ((luma - g) * desat) / 255;
      b += ((luma - b) * desat) / 255;
    }
    if (veil > 0) {
      const int keep = 255 - veil;
      r = (r * keep + kVeilR * veil) / 255;
      g = (g * keep + kVeilG * veil) / 255;
      b = (b * keep + kVeilB * veil) / 255;
    }
    px = 0xFF000000u | (static_cast<uint32_t>(r) << 16) |
         (static_cast<uint32_t>(g) << 8) | static_cast<uint32_t>(b);
  }
}

/**
 * Builds the plate drawn behind the segmented person: the chosen still image
 * when one is set, otherwise a veiled blur of the camera frame.
 */
static const std::vector<uint32_t>& BackgroundPlate(
    MeetVideoEffectsEngineImpl* impl,
    const std::vector<uint32_t>& input,
    int w,
    int h) {
  if (impl->UsesReplacementImage()) {
    if (impl->replacement_plate_width != w ||
        impl->replacement_plate_height != h) {
      ResizeArgbCover(impl->replacement_argb, impl->replacement_width,
                      impl->replacement_height, &impl->replacement_plate, w, h);
      impl->replacement_plate_width = w;
      impl->replacement_plate_height = h;
    }
    return impl->replacement_plate;
  }

  const int ds_w = std::max(8, static_cast<int>(w * kBlurDownsample));
  const int ds_h = std::max(8, static_cast<int>(h * kBlurDownsample));
  std::vector<uint32_t> small;
  ResizeArgbNearest(input, w, h, &small, ds_w, ds_h);
  const int radius = BlurRadiusForSigma(impl->blur_sigma);
  for (int i = 0; i < 3; ++i) BoxBlurArgb(&small, ds_w, ds_h, radius);
  ResizeArgbNearest(small, ds_w, ds_h, &impl->blurred_work, w, h);
  ApplyObscureVeil(&impl->blurred_work, impl->obscure_opacity);
  return impl->blurred_work;
}

/**
 * Shapes the raw segmentation alpha in `impl->mask_small` into the mask used
 * for blending.
 *
 * Runs Apple's stages in Apple's order — erode, solidify, feather, gamma —
 * because the order is what keeps the dials independent: erosion moves the
 * outline without reshaping the ramp, solidify fixes interior translucency
 * while leaving a narrow boundary ramp, and the feather then widens that ramp
 * into the visible soft edge.
 *
 * Apple runs all of this after upscaling to frame resolution. Doing that here
 * would mean per-pixel loops over ~900 k pixels on the capture thread, so like
 * Android we work in mask space and convert the frame-height fractions to mask
 * pixels. The cost is quantisation: one mask pixel is several frame pixels, so
 * sub-pixel erode radii round away rather than nudging the outline.
 */
static void ShapeMaskEdge(MeetVideoEffectsEngineImpl* impl) {
  const MaskEdgeTuning edge = impl->mask_edge;
  impl->EnsureToneLuts();
  ErodeMask(&impl->mask_small, kSegmenterSize, kSegmenterSize,
            edge.erode_height_fraction * kSegmenterSize);
  if (edge.solidify_slope > 1.f) {
    ApplyLut(&impl->mask_small, impl->solidify_lut);
  }
  FeatherMask(&impl->mask_small, kSegmenterSize, kSegmenterSize,
              std::max(edge.feather_height_fraction * kSegmenterSize,
                       kMaskFeatherSigmaFloor));
  if (edge.foreground_gamma != 1.f) {
    ApplyLut(&impl->mask_small, impl->gamma_lut);
  }
}

static void Compose(
    MeetVideoEffectsEngineImpl* impl,
    const std::vector<uint32_t>& input,
    int w,
    int h,
    const std::vector<uint8_t>& mask,
    int mw,
    int mh,
    std::vector<uint32_t>* out) {
  out->assign(input.begin(), input.end());
  const std::vector<uint32_t>& plate = BackgroundPlate(impl, input, w, h);
  std::vector<uint8_t> mask_up(static_cast<size_t>(w * h));
  for (int y = 0; y < h; ++y) {
    for (int x = 0; x < w; ++x) {
      const int sx = std::clamp(x * mw / std::max(w, 1), 0, mw - 1);
      const int sy = std::clamp(y * mh / std::max(h, 1), 0, mh - 1);
      mask_up[y * w + x] = mask[sy * mw + sx];
    }
  }
  for (int i = 0; i < w * h; ++i) {
    const uint8_t a = mask_up[i];
    const uint32_t fg = input[i];
    const uint32_t bg = plate[i];
    const int af = a;
    const int ab = 255 - a;
    const int r = (((fg >> 16) & 0xFF) * af + ((bg >> 16) & 0xFF) * ab) / 255;
    const int g = (((fg >> 8) & 0xFF) * af + ((bg >> 8) & 0xFF) * ab) / 255;
    const int b = ((fg & 0xFF) * af + (bg & 0xFF) * ab) / 255;
    (*out)[i] = 0xFF000000u | (r << 16) | (g << 8) | b;
  }
}

bool meet_video_effects_process_i420(
    MeetVideoEffectsEngine* engine,
    int width,
    int height,
    int rotation_degrees,
    const uint8_t* src_y,
    int stride_y,
    const uint8_t* src_u,
    int stride_u,
    const uint8_t* src_v,
    int stride_v,
    const uint8_t** out_y,
    int* out_stride_y,
    const uint8_t** out_u,
    int* out_stride_u,
    const uint8_t** out_v,
    int* out_stride_v,
    int* out_width,
    int* out_height) {
  if (!engine || !engine->impl.ready) return false;
  (void)rotation_degrees;
  std::lock_guard<std::mutex> lock(engine->impl.mutex);
#ifdef MEET_VIDEO_EFFECTS_USE_TFLITE
  int tw = 0, th = 0;
  ComputeTargetSize(width, height, kProcessingLongSide, &tw, &th);
  I420Buffer input;
  input.width = tw;
  input.height = th;
  input.stride_y = tw;
  input.stride_u = tw / 2;
  input.stride_v = tw / 2;
  input.y.resize(static_cast<size_t>(tw * th));
  input.u.resize(static_cast<size_t>((tw / 2) * (th / 2)));
  input.v.resize(static_cast<size_t>((tw / 2) * (th / 2)));
  for (int y = 0; y < th; ++y) {
    const int sy = y * height / th;
    for (int x = 0; x < tw; ++x) {
      const int sx = x * width / tw;
      input.y[y * tw + x] = src_y[sy * stride_y + sx];
    }
  }
  for (int y = 0; y < th / 2; ++y) {
    const int sy = y * (height / 2) / (th / 2);
    for (int x = 0; x < tw / 2; ++x) {
      const int sx = x * (width / 2) / (tw / 2);
      input.u[y * input.stride_u + x] = src_u[sy * stride_u + sx];
      input.v[y * input.stride_v + x] = src_v[sy * stride_v + sx];
    }
  }
  I420ToArgb(input, &engine->impl.argb_work);
  std::vector<uint32_t> small256;
  ResizeArgbNearest(engine->impl.argb_work, tw, th, &small256, kSegmenterSize, kSegmenterSize);
  engine->impl.mask_small = engine->impl.segmenter->Segment(small256);
  ShapeMaskEdge(&engine->impl);
  // Composed straight into the retained buffer: it feeds both the I420 result
  // below and any preview reading it back, and reusing it keeps the per-frame
  // allocation out of the capture thread.
  Compose(&engine->impl, engine->impl.argb_work, tw, th,
          engine->impl.mask_small, kSegmenterSize, kSegmenterSize,
          &engine->impl.last_composed);
  ArgbToI420(engine->impl.last_composed, tw, th, &engine->impl.output_i420);
  engine->impl.last_composed_width = tw;
  engine->impl.last_composed_height = th;
  *out_y = engine->impl.output_i420.y.data();
  *out_stride_y = engine->impl.output_i420.stride_y;
  *out_u = engine->impl.output_i420.u.data();
  *out_stride_u = engine->impl.output_i420.stride_u;
  *out_v = engine->impl.output_i420.v.data();
  *out_stride_v = engine->impl.output_i420.stride_v;
  *out_width = tw;
  *out_height = th;
  return true;
#else
  (void)width;
  (void)height;
  (void)src_y;
  (void)stride_y;
  (void)src_u;
  (void)stride_u;
  (void)src_v;
  (void)stride_v;
  (void)out_y;
  (void)out_stride_y;
  (void)out_u;
  (void)out_stride_u;
  (void)out_v;
  (void)out_stride_v;
  (void)out_width;
  (void)out_height;
  return false;
#endif
}

bool meet_video_effects_has_tflite(void) {
#ifdef MEET_VIDEO_EFFECTS_USE_TFLITE
  return true;
#else
  return false;
#endif
}

bool meet_video_effects_copy_last_frame_rgba(MeetVideoEffectsEngine* engine,
                                             uint8_t* dst,
                                             size_t dst_capacity,
                                             int* out_width,
                                             int* out_height) {
  if (!engine) return false;
  std::lock_guard<std::mutex> lock(engine->impl.mutex);

  const int w = engine->impl.last_composed_width;
  const int h = engine->impl.last_composed_height;
  if (w <= 0 || h <= 0) return false;
  const size_t pixels = static_cast<size_t>(w) * static_cast<size_t>(h);
  if (engine->impl.last_composed.size() < pixels) return false;

  if (out_width) *out_width = w;
  if (out_height) *out_height = h;
  // Size query: report the dimensions and let the caller allocate.
  if (!dst) return false;
  if (dst_capacity < pixels * 4) return false;

  // 0xAARRGGBB words out, R,G,B,A bytes in: the red and blue channels swap.
  const uint32_t* src = engine->impl.last_composed.data();
  for (size_t i = 0; i < pixels; ++i) {
    const uint32_t px = src[i];
    dst[i * 4 + 0] = static_cast<uint8_t>((px >> 16) & 0xFF);
    dst[i * 4 + 1] = static_cast<uint8_t>((px >> 8) & 0xFF);
    dst[i * 4 + 2] = static_cast<uint8_t>(px & 0xFF);
    dst[i * 4 + 3] = static_cast<uint8_t>((px >> 24) & 0xFF);
  }
  return true;
}
