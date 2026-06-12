#include "proton_rnnoise_processor.h"

#include <algorithm>
#include <cstring>
#include <rnnoise.h>

namespace proton_rnnoise {

namespace {

template <size_t kChannels>
float ProcessInterleavedFixed(DenoiseState *state, size_t frame_size,
                              float *samples, size_t sample_count) {
  constexpr size_t channels = kChannels;
  if (frame_size == 0 || sample_count % channels != 0) {
    return 0.f;
  }

  const size_t samples_per_channel = sample_count / channels;
  float vad = 0.f;

  for (size_t ch = 0; ch < channels; ++ch) {
    float in_frame[512];
    float out_frame[512];
    if (frame_size > sizeof(in_frame) / sizeof(in_frame[0])) {
      return vad;
    }

    // Live capture: one RNNoise frame per call (iOS / Android WebRTC).
    if (samples_per_channel == frame_size) {
      for (size_t i = 0; i < frame_size; ++i) {
        in_frame[i] = samples[i * channels + ch];
      }
      vad = rnnoise_process_frame(state, out_frame, in_frame);
      for (size_t i = 0; i < frame_size; ++i) {
        samples[i * channels + ch] = out_frame[i];
      }
      continue;
    }

    // Offline / batch: RNNoise v0.2 outputs one frame behind — align writes.
    size_t prev_frame_start{};
    bool has_prev_frame = false;
    for (size_t frame_start = 0;
         frame_start + frame_size <= samples_per_channel;
         frame_start += frame_size) {
      for (size_t i = 0; i < frame_size; ++i) {
        in_frame[i] = samples[(frame_start + i) * channels + ch];
      }

      vad = rnnoise_process_frame(state, out_frame, in_frame);

      if (has_prev_frame) {
        for (size_t i = 0; i < frame_size; ++i) {
          samples[(prev_frame_start + i) * channels + ch] = out_frame[i];
        }
      }
      prev_frame_start = frame_start;
      has_prev_frame = true;
    }

    if (has_prev_frame) {
      std::memset(in_frame, 0, frame_size * sizeof(float));
      vad = rnnoise_process_frame(state, out_frame, in_frame);
      for (size_t i = 0; i < frame_size; ++i) {
        samples[(prev_frame_start + i) * channels + ch] = out_frame[i];
      }
    }
  }

  return vad;
}

} // namespace

RnnoiseProcessor::RnnoiseProcessor()
    : enabled_(false), state_(nullptr), frame_size_(0) {
  state_ = rnnoise_create(nullptr);
  const int rnnoise_frame_size = rnnoise_get_frame_size();
  if (rnnoise_frame_size > 0) {
    frame_size_ = static_cast<size_t>(rnnoise_frame_size);
  }
}

RnnoiseProcessor::~RnnoiseProcessor() {
  if (state_ != nullptr) {
    rnnoise_destroy(state_);
    state_ = nullptr;
  }
}

void RnnoiseProcessor::Enable() { enabled_ = true; }

void RnnoiseProcessor::Disable() { enabled_ = false; }

bool RnnoiseProcessor::IsEnabled() const { return enabled_; }

int RnnoiseProcessor::frame_size() const {
  return static_cast<int>(frame_size_);
}

float RnnoiseProcessor::ProcessInterleaved(float *samples, size_t sample_count,
                                           int num_channels) {
  if (!enabled_ || state_ == nullptr || samples == nullptr ||
      sample_count == 0 || num_channels <= 0) {
    return 0.f;
  }

  if (num_channels == 1) {
    return ProcessInterleavedFixed<1>(state_, frame_size_, samples,
                                      sample_count);
  }
  if (num_channels == 2) {
    return ProcessInterleavedFixed<2>(state_, frame_size_, samples,
                                      sample_count);
  }
  return 0.f;
}

AudioProcessingManager &AudioProcessingManager::Instance() {
  static AudioProcessingManager instance;
  return instance;
}

AudioProcessingManager::AudioProcessingManager()
    : processor_(std::make_unique<RnnoiseProcessor>()),
      denoise_enabled_(false) {}

AudioProcessingManager::~AudioProcessingManager() = default;

void AudioProcessingManager::EnableDenoise() {
  processor_->Enable();
  denoise_enabled_ = true;
}

void AudioProcessingManager::DisableDenoise() {
  processor_->Disable();
  denoise_enabled_ = false;
}

bool AudioProcessingManager::IsDenoiseEnabled() const {
  return denoise_enabled_ && processor_->IsEnabled();
}

} // namespace proton_rnnoise
