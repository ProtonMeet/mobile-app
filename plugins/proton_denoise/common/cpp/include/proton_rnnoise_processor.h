#ifndef PROTON_RNNOISE_PROCESSOR_H_
#define PROTON_RNNOISE_PROCESSOR_H_

#include <cstddef>
#include <memory>

struct DenoiseState;

namespace proton_rnnoise {

class RnnoiseProcessor {
 public:
  RnnoiseProcessor();
  ~RnnoiseProcessor();

  RnnoiseProcessor(const RnnoiseProcessor&) = delete;
  RnnoiseProcessor& operator=(const RnnoiseProcessor&) = delete;

  void Enable();
  void Disable();
  bool IsEnabled() const;

  int frame_size() const;

  /// Processes interleaved float PCM in-place. Returns last VAD score.
  float ProcessInterleaved(float* samples, size_t sample_count, int num_channels);

 private:
  bool enabled_;
  DenoiseState* state_;
  size_t frame_size_;
};

class AudioProcessingManager {
 public:
  static AudioProcessingManager& Instance();

  void EnableDenoise();
  void DisableDenoise();
  bool IsDenoiseEnabled() const;

  RnnoiseProcessor& processor() { return *processor_; }

 private:
  AudioProcessingManager();
  ~AudioProcessingManager();

  std::unique_ptr<RnnoiseProcessor> processor_;
  bool denoise_enabled_;
};

}  // namespace proton_rnnoise

#endif  // PROTON_RNNOISE_PROCESSOR_H_
