/*
 * Copyright (c) 2026 Proton AG
 * C API for desktop (Linux/Windows) camera background blur.
 * Inference: TensorFlow Lite. Compositing: CPU I420/ARGB (same pipeline as Android).
 */

#ifndef MEET_VIDEO_EFFECTS_H_
#define MEET_VIDEO_EFFECTS_H_

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct MeetVideoEffectsEngine MeetVideoEffectsEngine;

/** Creates an engine; loads [model_path] (.tflite). Returns NULL on failure. */
MeetVideoEffectsEngine* meet_video_effects_create(const char* model_path);

void meet_video_effects_destroy(MeetVideoEffectsEngine* engine);

/** True when TFLite model is loaded and ready for inference. */
bool meet_video_effects_is_ready(const MeetVideoEffectsEngine* engine);

/**
 * Processes one camera frame in I420 (libwebrtc layout).
 * [src_y], [src_u], [src_v] are plane pointers; strides in bytes.
 * Output is written into engine-owned reusable buffers; pointers valid until next
 * process call or destroy.
 * Returns false to pass the frame through unchanged.
 */
bool meet_video_effects_process_i420(
    MeetVideoEffectsEngine* engine,
    int width,
    int height,
    int rotation_degrees,
    const uint8_t* src_y,
    int stride_y,
    const uint8_t* src_u,
    int stride_u,
    const uint8_t* src_v,
    int stride_v,
    const uint8_t** out_y,
    int* out_stride_y,
    const uint8_t** out_u,
    int* out_stride_u,
    const uint8_t** out_v,
    int* out_stride_v,
    int* out_width,
    int* out_height);

#ifdef __cplusplus
}
#endif

#endif  // MEET_VIDEO_EFFECTS_H_
