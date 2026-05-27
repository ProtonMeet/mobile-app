#include "proton_deepfilter_api.h"

#include <memory>
#include <stddef.h>

struct ProtonDeepFilterHandle {
  int enabled;
  int frame_size;
};

extern "C" {

ProtonDeepFilterHandle* proton_deepfilter_create(void) {
  auto* handle = new ProtonDeepFilterHandle();
  handle->enabled = 0;
  handle->frame_size = 480;
  return handle;
}

void proton_deepfilter_destroy(ProtonDeepFilterHandle* handle) {
  std::unique_ptr<ProtonDeepFilterHandle>(handle).reset();
}

int proton_deepfilter_get_frame_size(void) {
  return 480;
}

void proton_deepfilter_set_enabled(ProtonDeepFilterHandle* handle, int enabled) {
  if (handle != nullptr) {
    handle->enabled = enabled;
  }
}

int proton_deepfilter_is_enabled(ProtonDeepFilterHandle* handle) {
  return handle != nullptr && handle->enabled != 0 ? 1 : 0;
}

float proton_deepfilter_process_interleaved(ProtonDeepFilterHandle* handle,
                                            float* samples,
                                            size_t sample_count,
                                            int num_channels) {
  (void)samples;
  (void)sample_count;
  (void)num_channels;
  if (handle == nullptr || !handle->enabled) {
    return 0.f;
  }
  return 0.f;
}

}  // extern "C"
