#include "proton_rnnoise_api.h"

#include <memory>
#include <rnnoise.h>

#include "proton_rnnoise_processor.h"

struct ProtonRnnoiseHandle {
  std::unique_ptr<proton_rnnoise::RnnoiseProcessor> processor;
};

extern "C" {

ProtonRnnoiseHandle* proton_rnnoise_create(void) {
  auto processor = std::make_unique<proton_rnnoise::RnnoiseProcessor>();
  if (processor == nullptr) {
    return nullptr;
  }
  auto* handle = new ProtonRnnoiseHandle{std::move(processor)};
  return handle;
}

void proton_rnnoise_destroy(ProtonRnnoiseHandle* handle) {
  std::unique_ptr<ProtonRnnoiseHandle>(handle).reset();
}

int proton_rnnoise_get_frame_size(void) {
  return rnnoise_get_frame_size();
}

void proton_rnnoise_set_enabled(ProtonRnnoiseHandle* handle, int enabled) {
  if (handle == nullptr || handle->processor == nullptr) {
    return;
  }
  if (enabled) {
    handle->processor->Enable();
  } else {
    handle->processor->Disable();
  }
}

int proton_rnnoise_is_enabled(ProtonRnnoiseHandle* handle) {
  if (handle == nullptr || handle->processor == nullptr) {
    return 0;
  }
  return handle->processor->IsEnabled() ? 1 : 0;
}

float proton_rnnoise_process_interleaved(ProtonRnnoiseHandle* handle,
                                         float* samples,
                                         size_t sample_count,
                                         int num_channels) {
  if (handle == nullptr || handle->processor == nullptr) {
    return 0.f;
  }
  return handle->processor->ProcessInterleaved(samples, sample_count,
                                               num_channels);
}

}  // extern "C"
