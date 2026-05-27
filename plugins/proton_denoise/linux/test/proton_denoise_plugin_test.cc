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
  const auto result = DesktopAudioDenoise::Instance().Handle(
      "me.proton.meet/denoise", "listDenoiseTypes", "", "", false);
  EXPECT_TRUE(result.success);
  EXPECT_FALSE(result.json_list_payload.empty());
}

}  // namespace test
}  // namespace proton_denoise
