#include "proton_deepfilter_api.h"

#include <algorithm>
#include <cstring>
#include <memory>
#include <string>

#include "deep_filter.h"

namespace {

template <size_t kChannels>
float ProcessInterleavedFixed(DFState* state, size_t frame_size, float* samples,
                              size_t sample_count) {
  constexpr size_t channels = kChannels;
  if (state == nullptr || frame_size == 0 || sample_count % channels != 0) {
    return 0.f;
  }

  const size_t samples_per_channel = sample_count / channels;
  float snr = 0.f;

  for (size_t ch = 0; ch < channels; ++ch) {
    float in_frame[512];
    float out_frame[512];
    if (frame_size > sizeof(in_frame) / sizeof(in_frame[0])) {
      return snr;
    }

    if (samples_per_channel == frame_size) {
      for (size_t i = 0; i < frame_size; ++i) {
        in_frame[i] = samples[i * channels + ch];
      }
      snr = df_process_frame(state, in_frame, out_frame);
      for (size_t i = 0; i < frame_size; ++i) {
        samples[i * channels + ch] = out_frame[i];
      }
      continue;
    }

    for (size_t frame_start = 0; frame_start + frame_size <= samples_per_channel;
         frame_start += frame_size) {
      for (size_t i = 0; i < frame_size; ++i) {
        in_frame[i] = samples[(frame_start + i) * channels + ch];
      }
      snr = df_process_frame(state, in_frame, out_frame);
      for (size_t i = 0; i < frame_size; ++i) {
        samples[(frame_start + i) * channels + ch] = out_frame[i];
      }
    }
  }

  return snr;
}

}  // namespace

struct ProtonDeepFilterHandle {
  DFState* state;
  size_t frame_size;
  bool enabled;
};

extern "C" {

int proton_deepfilter_ensure_loaded() {
  return 1;
}

ProtonDeepFilterHandle* proton_deepfilter_create(const char* model_path) {
  if (model_path == nullptr || model_path[0] == '\0') {
    return nullptr;
  }
  DFState* state = df_create(model_path, 100.f, nullptr);
  if (state == nullptr) {
    return nullptr;
  }
  const size_t frame_size = df_get_frame_length(state);
  if (frame_size == 0) {
    df_free(state);
    return nullptr;
  }
  return new ProtonDeepFilterHandle{state, frame_size, false};
}

void proton_deepfilter_destroy(ProtonDeepFilterHandle* handle) {
  if (handle == nullptr) {
    return;
  }
  std::unique_ptr<ProtonDeepFilterHandle> owned(handle);
  if (owned->state != nullptr) {
    df_free(owned->state);
    owned->state = nullptr;
  }
}

int proton_deepfilter_get_frame_size(ProtonDeepFilterHandle* handle) {
  if (handle == nullptr) {
    return 0;
  }
  return static_cast<int>(handle->frame_size);
}

void proton_deepfilter_set_enabled(ProtonDeepFilterHandle* handle, int enabled) {
  if (handle != nullptr) {
    handle->enabled = enabled != 0;
  }
}

int proton_deepfilter_is_enabled(ProtonDeepFilterHandle* handle) {
  return handle != nullptr && handle->enabled ? 1 : 0;
}

void proton_deepfilter_set_atten_lim(ProtonDeepFilterHandle* handle, float lim_db) {
  if (handle != nullptr && handle->state != nullptr) {
    df_set_atten_lim(handle->state, lim_db);
  }
}

float proton_deepfilter_process_interleaved(ProtonDeepFilterHandle* handle,
                                            float* samples, size_t sample_count,
                                            int num_channels) {
  if (handle == nullptr || handle->state == nullptr || !handle->enabled ||
      samples == nullptr || sample_count == 0 || num_channels <= 0) {
    return 0.f;
  }

  if (num_channels == 1) {
    return ProcessInterleavedFixed<1>(handle->state, handle->frame_size, samples,
                                      sample_count);
  }
  if (num_channels == 2) {
    return ProcessInterleavedFixed<2>(handle->state, handle->frame_size, samples,
                                      sample_count);
  }
  return 0.f;
}

}  // extern "C"
