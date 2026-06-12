#ifndef DTLN_H_
#define DTLN_H_

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct DtlnHandle DtlnHandle;

DtlnHandle* dtln_create(void);
void dtln_destroy(DtlnHandle* handle);
void dtln_stop(DtlnHandle* handle);

int dtln_get_sample_rate(void);
int dtln_get_block_shift(void);

/** In-place denoise: input/output are 16 kHz mono float PCM. Returns 0 on success. */
int dtln_denoise(DtlnHandle* handle,
                 const float* input,
                 float* output,
                 int sample_count);

#ifdef __cplusplus
}
#endif

#endif /* DTLN_H_ */
