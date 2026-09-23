/*
 * Copyright (c) 2026 Proton AG
 * Engine tests for the desktop (Linux/Windows) background blur / virtual
 * background pipeline. These run against the real `selfie_segmenter.tflite`,
 * so they only build when TFLite is enabled (see native/README.md).
 */

#include <gtest/gtest.h>

#include <cstring>
#include <memory>
#include <vector>

#include "meet_video_effects.h"

namespace {

constexpr int kWidth = 640;
constexpr int kHeight = 480;

/// A bright rectangle on a dark field. The engine only has to cope with
/// non-uniform input; these tests assert on pipeline behaviour, not on where
/// the segmenter decides the person is.
class SyntheticFrame {
 public:
  SyntheticFrame()
      : y_(static_cast<size_t>(kWidth) * kHeight),
        u_(static_cast<size_t>(kWidth / 2) * (kHeight / 2)),
        v_(static_cast<size_t>(kWidth / 2) * (kHeight / 2)) {
    for (int row = 0; row < kHeight; ++row) {
      for (int col = 0; col < kWidth; ++col) {
        const bool subject = row > kHeight / 4 && row < kHeight * 3 / 4 &&
                             col > kWidth / 3 && col < kWidth * 2 / 3;
        y_[static_cast<size_t>(row) * kWidth + col] = subject ? 200 : 40;
      }
    }
    std::memset(u_.data(), 128, u_.size());
    std::memset(v_.data(), 128, v_.size());
  }

  /// Runs one frame and checks the engine handed back a usable I420 buffer.
  ::testing::AssertionResult ProcessedBy(MeetVideoEffectsEngine* engine) const {
    const uint8_t *out_y = nullptr, *out_u = nullptr, *out_v = nullptr;
    int stride_y = 0, stride_u = 0, stride_v = 0, width = 0, height = 0;
    if (!meet_video_effects_process_i420(
            engine, kWidth, kHeight, /*rotation_degrees=*/0, y_.data(), kWidth,
            u_.data(), kWidth / 2, v_.data(), kWidth / 2, &out_y, &stride_y,
            &out_u, &stride_u, &out_v, &stride_v, &width, &height)) {
      return ::testing::AssertionFailure() << "frame was passed through unchanged";
    }
    if (!out_y || !out_u || !out_v) {
      return ::testing::AssertionFailure() << "engine returned a null plane";
    }
    if (width != kWidth || height != kHeight) {
      return ::testing::AssertionFailure()
             << "expected " << kWidth << "x" << kHeight << ", got " << width
             << "x" << height;
    }
    if (stride_y < kWidth || stride_u < kWidth / 2 || stride_v < kWidth / 2) {
      return ::testing::AssertionFailure()
             << "strides too small: " << stride_y << "/" << stride_u << "/"
             << stride_v;
    }
    return ::testing::AssertionSuccess();
  }

 private:
  std::vector<uint8_t> y_, u_, v_;
};

struct EngineDeleter {
  void operator()(MeetVideoEffectsEngine* e) const { meet_video_effects_destroy(e); }
};
using EnginePtr = std::unique_ptr<MeetVideoEffectsEngine, EngineDeleter>;

EnginePtr MakeEngine() {
  return EnginePtr(meet_video_effects_create(MEET_VIDEO_EFFECTS_TEST_MODEL_PATH));
}

std::vector<uint8_t> SolidRgba(int width, int height) {
  return std::vector<uint8_t>(static_cast<size_t>(width) * height * 4, 0x7f);
}

// The bundled model is a MediaPipe export and needs the custom operator
// `Convolution2DTransposeBias`, which stock TFLite does not implement. Without
// it the interpreter fails to build and every other test here fails too, so
// keep this as its own named case to make the cause obvious.
TEST(MeetVideoEffectsEngine, LoadsModelRequiringMediaPipeCustomOp) {
  const EnginePtr engine = MakeEngine();
  ASSERT_NE(engine, nullptr) << "model failed to load — is the custom op registered?";
  EXPECT_TRUE(meet_video_effects_is_ready(engine.get()));
}

TEST(MeetVideoEffectsEngine, RejectsMissingModel) {
  EXPECT_EQ(meet_video_effects_create("does-not-exist.tflite"), nullptr);
  EXPECT_EQ(meet_video_effects_create(""), nullptr);
  EXPECT_EQ(meet_video_effects_create(nullptr), nullptr);
}

TEST(MeetVideoEffectsEngine, BlursFrames) {
  const EnginePtr engine = MakeEngine();
  ASSERT_NE(engine, nullptr);
  const SyntheticFrame frame;

  meet_video_effects_set_background_mode(engine.get(), kMeetVideoEffectsBackgroundBlur);
  meet_video_effects_set_blur_config(engine.get(), /*blur_sigma=*/128.f,
                                     /*background_obscure_opacity=*/0.f);
  EXPECT_TRUE(frame.ProcessedBy(engine.get()));
  // Output buffers are reused between calls, so a second frame exercises the
  // reuse path rather than first-time allocation.
  EXPECT_TRUE(frame.ProcessedBy(engine.get()));
}

// Backs the desktop self-view: the preview reads composited pixels back out of
// the engine instead of re-running the pipeline.
TEST(MeetVideoEffectsEngine, CopiesComposedFrameAsRgba) {
  const EnginePtr engine = MakeEngine();
  ASSERT_NE(engine, nullptr);
  const SyntheticFrame frame;

  int width = -1, height = -1;
  // Nothing composed yet, so there is nothing to hand back.
  EXPECT_FALSE(meet_video_effects_copy_last_frame_rgba(engine.get(), nullptr, 0,
                                                       &width, &height));

  ASSERT_TRUE(frame.ProcessedBy(engine.get()));

  // A null destination is the size query: dimensions come back, pixels do not.
  EXPECT_FALSE(meet_video_effects_copy_last_frame_rgba(engine.get(), nullptr, 0,
                                                       &width, &height));
  EXPECT_EQ(width, kWidth);
  EXPECT_EQ(height, kHeight);

  std::vector<uint8_t> rgba(static_cast<size_t>(width) * height * 4, 0);
  // One byte short must be refused rather than overrun the caller's buffer.
  EXPECT_FALSE(meet_video_effects_copy_last_frame_rgba(
      engine.get(), rgba.data(), rgba.size() - 1, &width, &height));

  ASSERT_TRUE(meet_video_effects_copy_last_frame_rgba(
      engine.get(), rgba.data(), rgba.size(), &width, &height));

  // Opaque alpha throughout, and the frame must not be uniformly black — that
  // would mean the channel swap dropped the image rather than reordering it.
  bool any_colour = false;
  for (size_t i = 0; i < rgba.size(); i += 4) {
    ASSERT_EQ(rgba[i + 3], 0xFF) << "alpha at pixel " << (i / 4);
    any_colour |= (rgba[i] | rgba[i + 1] | rgba[i + 2]) != 0;
  }
  EXPECT_TRUE(any_colour);
}

TEST(MeetVideoEffectsEngine, ImageModeFallsBackToBlurUntilImageIsSet) {
  const EnginePtr engine = MakeEngine();
  ASSERT_NE(engine, nullptr);
  const SyntheticFrame frame;

  meet_video_effects_set_background_mode(engine.get(), kMeetVideoEffectsBackgroundImage);
  EXPECT_TRUE(frame.ProcessedBy(engine.get()))
      << "image mode must not drop frames before an image arrives";

  const std::vector<uint8_t> rgba = SolidRgba(64, 64);
  EXPECT_TRUE(meet_video_effects_set_replacement_image(engine.get(), rgba.data(), 64, 64));
  EXPECT_TRUE(frame.ProcessedBy(engine.get()));
}

TEST(MeetVideoEffectsEngine, ScalesReplacementImagesOfAnyAspect) {
  const EnginePtr engine = MakeEngine();
  ASSERT_NE(engine, nullptr);
  const SyntheticFrame frame;
  meet_video_effects_set_background_mode(engine.get(), kMeetVideoEffectsBackgroundImage);

  for (const auto& size : {std::pair<int, int>{16, 256}, {256, 16}, {1, 1}, {1920, 1080}}) {
    const std::vector<uint8_t> rgba = SolidRgba(size.first, size.second);
    EXPECT_TRUE(meet_video_effects_set_replacement_image(engine.get(), rgba.data(),
                                                         size.first, size.second))
        << size.first << "x" << size.second;
    EXPECT_TRUE(frame.ProcessedBy(engine.get())) << size.first << "x" << size.second;
  }
}

// Per meet_video_effects.h: null pixels clear the image (a valid request),
// whereas non-null pixels with a bad size are a decode failure.
TEST(MeetVideoEffectsEngine, ReplacementImageContract) {
  const EnginePtr engine = MakeEngine();
  ASSERT_NE(engine, nullptr);
  const std::vector<uint8_t> rgba = SolidRgba(64, 64);

  EXPECT_FALSE(meet_video_effects_set_replacement_image(engine.get(), rgba.data(), 0, 0));
  EXPECT_FALSE(meet_video_effects_set_replacement_image(engine.get(), rgba.data(), -1, 64));
  EXPECT_TRUE(meet_video_effects_set_replacement_image(engine.get(), nullptr, 64, 64));

  const SyntheticFrame frame;
  meet_video_effects_set_background_mode(engine.get(), kMeetVideoEffectsBackgroundImage);
  EXPECT_TRUE(frame.ProcessedBy(engine.get()))
      << "clearing the image must fall back to blur, not drop frames";
}

TEST(MeetVideoEffectsEngine, ToleratesOutOfRangeBlurConfig) {
  const EnginePtr engine = MakeEngine();
  ASSERT_NE(engine, nullptr);
  const SyntheticFrame frame;

  // BackgroundBlurConfig clamps to 4..256 in Dart; native must not trust it.
  for (const float sigma : {-1.f, 0.f, 1.f, 4.f, 256.f, 1e6f}) {
    meet_video_effects_set_blur_config(engine.get(), sigma, /*obscure=*/0.5f);
    EXPECT_TRUE(frame.ProcessedBy(engine.get())) << "sigma " << sigma;
  }
  for (const float opacity : {-1.f, 0.f, 1.f, 2.f}) {
    meet_video_effects_set_blur_config(engine.get(), 128.f, opacity);
    EXPECT_TRUE(frame.ProcessedBy(engine.get())) << "opacity " << opacity;
  }
}

// The shaping stages run on the capture thread with radii derived from the
// caller's fractions, so an unclamped value would size a kernel rather than
// just look wrong. Dart clamps; native must not trust it.
TEST(MeetVideoEffectsEngine, ToleratesOutOfRangeMaskEdgeTuning) {
  const EnginePtr engine = MakeEngine();
  ASSERT_NE(engine, nullptr);
  const SyntheticFrame frame;

  struct Tuning {
    float feather, erode, slope, midpoint, gamma;
  };
  // Defaults, both ends of every documented range, and well past them.
  for (const Tuning t : {Tuning{0.010f, 0.002f, 6.f, 0.55f, 1.f},
                         Tuning{0.f, 0.f, 1.f, 0.2f, 0.5f},
                         Tuning{0.05f, 0.05f, 16.f, 0.8f, 3.f},
                         Tuning{-1.f, -1.f, -1.f, -1.f, -1.f},
                         Tuning{1e6f, 1e6f, 1e6f, 1e6f, 1e6f}}) {
    meet_video_effects_set_mask_edge_tuning(engine.get(), t.feather, t.erode,
                                            t.slope, t.midpoint, t.gamma);
    EXPECT_TRUE(frame.ProcessedBy(engine.get()))
        << "feather " << t.feather << " erode " << t.erode << " slope "
        << t.slope << " midpoint " << t.midpoint << " gamma " << t.gamma;
  }
}

TEST(MeetVideoEffectsEngine, IgnoresCallsOnNullEngine) {
  EXPECT_FALSE(meet_video_effects_is_ready(nullptr));
  EXPECT_FALSE(meet_video_effects_set_replacement_image(nullptr, nullptr, 0, 0));
  // Must not crash.
  meet_video_effects_set_background_mode(nullptr, kMeetVideoEffectsBackgroundBlur);
  meet_video_effects_set_blur_config(nullptr, 128.f, 0.f);
  meet_video_effects_set_mask_edge_tuning(nullptr, 0.01f, 0.002f, 6.f, 0.55f, 1.f);
  meet_video_effects_destroy(nullptr);
}

}  // namespace
