#include "proton_dtln_api.h"

#include <memory>

#include "dtln.h"

struct ProtonDtlnHandle {
  DtlnHandle* engine;
};

extern "C" {

ProtonDtlnHandle* proton_dtln_create(void) {
  DtlnHandle* engine = dtln_create();
  if (engine == nullptr) {
    return nullptr;
  }
  return new ProtonDtlnHandle{engine};
}

void proton_dtln_destroy(ProtonDtlnHandle* handle) {
  if (handle == nullptr) {
    return;
  }
  std::unique_ptr<ProtonDtlnHandle> owned(handle);
  if (owned->engine != nullptr) {
    dtln_destroy(owned->engine);
    owned->engine = nullptr;
  }
}

int proton_dtln_get_sample_rate(void) { return dtln_get_sample_rate(); }

int proton_dtln_get_block_shift(void) { return dtln_get_block_shift(); }

int proton_dtln_denoise_interleaved(ProtonDtlnHandle* handle,
                                    float* samples,
                                    size_t sample_count) {
  if (handle == nullptr || handle->engine == nullptr || samples == nullptr ||
      sample_count == 0) {
    return -1;
  }
  return dtln_denoise(handle->engine, samples, samples,
                    static_cast<int>(sample_count));
}

}  // extern "C"
