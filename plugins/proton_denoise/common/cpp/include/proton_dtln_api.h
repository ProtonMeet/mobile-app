#ifndef PROTON_DTLN_API_H_
#define PROTON_DTLN_API_H_

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#if defined(PROTON_DTLN_RS_BUILD)
#define PROTON_DTLN_EXPORT __declspec(dllexport)
#else
#define PROTON_DTLN_EXPORT __declspec(dllimport)
#endif
#else
#define PROTON_DTLN_EXPORT __attribute__((visibility("default")))
#endif

typedef struct ProtonDtlnHandle ProtonDtlnHandle;

PROTON_DTLN_EXPORT ProtonDtlnHandle* proton_dtln_create(void);
PROTON_DTLN_EXPORT void proton_dtln_destroy(ProtonDtlnHandle* handle);
PROTON_DTLN_EXPORT int proton_dtln_get_sample_rate(void);
PROTON_DTLN_EXPORT int proton_dtln_get_block_shift(void);

/** 16 kHz mono interleaved float PCM in-place. Returns 0 on success. */
PROTON_DTLN_EXPORT int proton_dtln_denoise_interleaved(ProtonDtlnHandle* handle,
                                                       float* samples,
                                                       size_t sample_count);

#ifdef __cplusplus
}
#endif

#endif  // PROTON_DTLN_API_H_
