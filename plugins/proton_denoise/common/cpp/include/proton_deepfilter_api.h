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

/// Voice-call default: caps noise suppression depth (dB). 100 = libDF unlimited.
#define PROTON_DEEPFILTER_DEFAULT_ATTEN_LIM_DB 30.f

typedef struct ProtonDeepFilterHandle ProtonDeepFilterHandle;

/// Resolves df_* symbols from libdeepfilter.so (dlopen / RTLD_DEFAULT). Returns 1 when ready.
PROTON_DEEPFILTER_EXPORT int proton_deepfilter_ensure_loaded();

/// Creates a DeepFilterNet instance from a tar.gz ONNX model path.
PROTON_DEEPFILTER_EXPORT ProtonDeepFilterHandle* proton_deepfilter_create(
    const char* model_path);

PROTON_DEEPFILTER_EXPORT void proton_deepfilter_destroy(
    ProtonDeepFilterHandle* handle);

/// Frame size in samples per channel (typically 480 @ 48 kHz).
PROTON_DEEPFILTER_EXPORT int proton_deepfilter_get_frame_size(
    ProtonDeepFilterHandle* handle);

PROTON_DEEPFILTER_EXPORT void proton_deepfilter_set_enabled(
    ProtonDeepFilterHandle* handle,
    int enabled);

PROTON_DEEPFILTER_EXPORT int proton_deepfilter_is_enabled(
    ProtonDeepFilterHandle* handle);

/// Attenuation limit in dB (e.g. 100 = no practical limit).
PROTON_DEEPFILTER_EXPORT void proton_deepfilter_set_atten_lim(
    ProtonDeepFilterHandle* handle,
    float lim_db);

/// In-place denoise for interleaved float PCM.
PROTON_DEEPFILTER_EXPORT float proton_deepfilter_process_interleaved(
    ProtonDeepFilterHandle* handle,
    float* samples,
    size_t sample_count,
    int num_channels);

#ifdef __cplusplus
}
#endif

#endif  // PROTON_DEEPFILTER_API_H_
