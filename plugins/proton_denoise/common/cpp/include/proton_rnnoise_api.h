#ifndef PROTON_RNNOISE_API_H_
#define PROTON_RNNOISE_API_H_

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#if defined(PROTON_RNNOISE_BUILD)
#define PROTON_RNNOISE_EXPORT __declspec(dllexport)
#else
#define PROTON_RNNOISE_EXPORT __declspec(dllimport)
#endif
#else
#define PROTON_RNNOISE_EXPORT __attribute__((visibility("default")))
#endif

typedef struct ProtonRnnoiseHandle ProtonRnnoiseHandle;

/// Creates an RNNoise denoiser instance. Returns NULL on failure.
PROTON_RNNOISE_EXPORT ProtonRnnoiseHandle* proton_rnnoise_create(void);

/// Destroys a handle created by proton_rnnoise_create.
PROTON_RNNOISE_EXPORT void proton_rnnoise_destroy(ProtonRnnoiseHandle* handle);

/// RNNoise frame size in samples (typically 480 @ 48 kHz).
PROTON_RNNOISE_EXPORT int proton_rnnoise_get_frame_size(void);

/// Enable or disable processing (1 = enabled, 0 = disabled).
PROTON_RNNOISE_EXPORT void proton_rnnoise_set_enabled(ProtonRnnoiseHandle* handle,
                                                      int enabled);

PROTON_RNNOISE_EXPORT int proton_rnnoise_is_enabled(ProtonRnnoiseHandle* handle);

/// In-place denoise for interleaved float PCM.
/// Returns voice-activity score for the last processed frame, or 0 if disabled.
PROTON_RNNOISE_EXPORT float proton_rnnoise_process_interleaved(
    ProtonRnnoiseHandle* handle,
    float* samples,
    size_t sample_count,
    int num_channels);

#ifdef __cplusplus
}
#endif

#endif  // PROTON_RNNOISE_API_H_
