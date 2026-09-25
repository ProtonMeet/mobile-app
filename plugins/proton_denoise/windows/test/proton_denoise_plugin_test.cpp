#include <gtest/gtest.h>

#include "../common/desktop/desktop_audio_denoise.h"

namespace proton_denoise {
namespace test {

TEST(DesktopAudioDenoise, LegacyGetFrameSize) {
  const auto result = DesktopAudioDenoise::Instance().Handle(
      "proton_denoise", "getFrameSize", "", "", false);
  EXPECT_TRUE(result.success);
  EXPECT_GT(result.int_value, 0);
}

TEST(DesktopAudioDenoise, ListDenoiseTypes) {
  const auto types = DesktopAudioDenoise::Instance().ListDenoiseTypes();
  ASSERT_EQ(types.size(), 3u);
  EXPECT_EQ(types[0].id, "rnnoise");
  EXPECT_TRUE(types[0].is_ready);
  EXPECT_EQ(types[1].id, "deepfilter");
  EXPECT_FALSE(types[1].is_ready);
  EXPECT_EQ(types[2].id, "dtln-rs");
  EXPECT_FALSE(types[2].is_ready);
}

// Dart checks isTypeReady before attach, so it must not depend on a handle
// that only attach creates.
TEST(DesktopAudioDenoise, RnnoiseIsReadyBeforeAttach) {
  const auto result = DesktopAudioDenoise::Instance().Handle(
      "me.proton.meet/denoise", "isTypeReady", "", "rnnoise", false);
  EXPECT_TRUE(result.success);
  EXPECT_TRUE(result.bool_value);
}

TEST(DesktopAudioDenoise, WarmUpRnnoise) {
  const auto entries = DesktopAudioDenoise::Instance().WarmUp("rnnoise");
  ASSERT_EQ(entries.size(), 1u);
  EXPECT_EQ(entries[0].id, "rnnoise");
  EXPECT_TRUE(entries[0].warm_up_ok);
}

}  // namespace test
}  // namespace proton_denoise
