#ifndef PROTON_DEEPFILTER_API_H_
#define PROTON_DEEPFILTER_API_H_

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#if defined(PROTON_DENOISE_BUILD)
#define PROTON_DEEPFILTER_EXPORT __declspec(dllexport)
#else
#define PROTON_DEEPFILTER_EXPORT __declspec(dllimport)
#endif
#else
#define PROTON_DEEPFILTER_EXPORT __attribute__((visibility("default")))
#endif

typedef struct ProtonDeepFilterHandle ProtonDeepFilterHandle;

PROTON_DEEPFILTER_EXPORT ProtonDeepFilterHandle* proton_deepfilter_create(void);

PROTON_DEEPFILTER_EXPORT void proton_deepfilter_destroy(ProtonDeepFilterHandle* handle);

PROTON_DEEPFILTER_EXPORT int proton_deepfilter_get_frame_size(void);

PROTON_DEEPFILTER_EXPORT void proton_deepfilter_set_enabled(ProtonDeepFilterHandle* handle,
                                                            int enabled);

PROTON_DEEPFILTER_EXPORT int proton_deepfilter_is_enabled(ProtonDeepFilterHandle* handle);

/// In-place pass-through until DeepFilter model is integrated.
PROTON_DEEPFILTER_EXPORT float proton_deepfilter_process_interleaved(
    ProtonDeepFilterHandle* handle,
    float* samples,
    size_t sample_count,
    int num_channels);

#ifdef __cplusplus
}
#endif

#endif  // PROTON_DEEPFILTER_API_H_
