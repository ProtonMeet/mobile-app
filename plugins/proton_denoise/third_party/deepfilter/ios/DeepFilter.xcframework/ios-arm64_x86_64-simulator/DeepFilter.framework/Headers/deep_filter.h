#ifndef DEEP_FILTER_H_
#define DEEP_FILTER_H_

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct DFState DFState;

DFState* df_create(const char* path, float atten_lim, const char* log_level);
size_t df_get_frame_length(DFState* st);
float df_process_frame(DFState* st, float* input, float* output);
void df_set_atten_lim(DFState* st, float lim_db);
void df_free(DFState* st);

#ifdef __cplusplus
}
#endif

#endif  // DEEP_FILTER_H_
