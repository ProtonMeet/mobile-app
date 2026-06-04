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
#include "tensorflow/lite/c/c_api.h"
#endif

namespace {

constexpr int kSegmenterSize = 256;
constexpr int kProcessingLongSide = 720;
constexpr float kBlurDownsample = 0.25f;
constexpr int kBlurRadius = 8;
constexpr float kMaskFeatherSigma = 1.5f;

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
      float* in = TfLiteTensorData(input);
      for (int i = 0; i < n; ++i) {
        const uint32_t px = argb256[i];
        in[i * 3 + 0] = ((px >> 16) & 0xFF) / 255.f;
        in[i * 3 + 1] = ((px >> 8) & 0xFF) / 255.f;
        in[i * 3 + 2] = (px & 0xFF) / 255.f;
      }
    }
    TfLiteInterpreterInvoke(interpreter);
    TfLiteTensor* output = TfLiteInterpreterGetOutputTensor(interpreter, 0);
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
  std::vector<uint32_t> blurred_work;
  I420Buffer output_i420;
  bool ready = false;
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

static void Compose(
    const std::vector<uint32_t>& input,
    int w,
    int h,
    const std::vector<uint8_t>& mask,
    int mw,
    int mh,
    std::vector<uint32_t>* out) {
  out->assign(input.begin(), input.end());
  const int ds_w = std::max(8, static_cast<int>(w * kBlurDownsample));
  const int ds_h = std::max(8, static_cast<int>(h * kBlurDownsample));
  std::vector<uint32_t> small;
  ResizeArgbNearest(input, w, h, &small, ds_w, ds_h);
  for (int i = 0; i < 3; ++i) BoxBlurArgb(&small, ds_w, ds_h, kBlurRadius);
  std::vector<uint32_t> blur_full;
  ResizeArgbNearest(small, ds_w, ds_h, &blur_full, w, h);
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
    const uint32_t bg = blur_full[i];
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
  FeatherMask(&engine->impl.mask_small, kSegmenterSize, kSegmenterSize, kMaskFeatherSigma);
  std::vector<uint32_t> composed;
  Compose(engine->impl.argb_work, tw, th, engine->impl.mask_small,
          kSegmenterSize, kSegmenterSize, &composed);
  ArgbToI420(composed, tw, th, &engine->impl.output_i420);
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
