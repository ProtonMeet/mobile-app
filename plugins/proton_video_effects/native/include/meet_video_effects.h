/*
 * Copyright (c) 2026 Proton AG
 * C API for desktop (Linux/Windows) camera background blur.
 * Inference: TensorFlow Lite. Compositing: CPU I420/ARGB (same pipeline as Android).
 */

#ifndef MEET_VIDEO_EFFECTS_H_
#define MEET_VIDEO_EFFECTS_H_

#include <stdbool.h>
#include <stddef.h>
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
 * True when this library was compiled with TensorFlow Lite inference enabled.
 *
 * Separates "the build has no inference at all" from "the model failed to
 * load", which [meet_video_effects_is_ready] alone cannot distinguish.
 */
bool meet_video_effects_has_tflite(void);

/** How the area behind the segmented person is filled (see CameraBackgroundMode). */
typedef enum {
  kMeetVideoEffectsBackgroundBlur = 0,
  kMeetVideoEffectsBackgroundImage = 1,
} MeetVideoEffectsBackgroundMode;

/**
 * Selects the background fill. Image mode falls back to blur while no
 * replacement image is set, so the caller never has to order the two calls.
 */
void meet_video_effects_set_background_mode(MeetVideoEffectsEngine* engine,
                                            MeetVideoEffectsBackgroundMode mode);

/**
 * [blur_sigma] follows BackgroundBlurConfig (4..256, default 128).
 * [background_obscure_opacity] (0..1) veils the blurred camera plate; it is not
 * applied to a replacement image.
 */
void meet_video_effects_set_blur_config(MeetVideoEffectsEngine* engine,
                                        float blur_sigma,
                                        float background_obscure_opacity);

/**
 * Shapes the segmentation mask before it is used to blend subject over
 * background, following Dart's `MaskEdgeTuning` and the Apple/Android stage
 * order: erode, solidify, feather, gamma.
 *
 * [feather_height_fraction] and [erode_height_fraction] are fractions of frame
 * height (0..0.05). Like Android, they are applied in mask space rather than at
 * frame resolution, which is equivalent because the mask is a scaled copy of
 * the frame; the cost is quantisation, so sub-pixel radii round away.
 *
 * [solidify_slope] (1..16, 1 disables the step) and [solidify_midpoint]
 * (0.2..0.8) stretch confidence into coverage so the subject's interior stops
 * blending translucent. [foreground_gamma] (0.5..3, 1 is neutral) is the final
 * tone curve on the shaped mask. Values are clamped to those ranges.
 */
void meet_video_effects_set_mask_edge_tuning(MeetVideoEffectsEngine* engine,
                                             float feather_height_fraction,
                                             float erode_height_fraction,
                                             float solidify_slope,
                                             float solidify_midpoint,
                                             float foreground_gamma);

/**
 * Sets the still image used in image mode. [rgba] is tightly packed
 * width*height*4 (R,G,B,A) and is copied, so the caller keeps ownership.
 * Pass NULL (or a zero size) to clear. Returns false when the pixels are
 * unusable, matching the Android/iOS "failed to decode" contract.
 */
bool meet_video_effects_set_replacement_image(MeetVideoEffectsEngine* engine,
                                              const uint8_t* rgba,
                                              int width,
                                              int height);

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

/**
 * Copies the most recently composed frame into [dst] as tightly packed RGBA
 * (byte order R,G,B,A — what Flutter's desktop pixel-buffer textures expect).
 *
 * A copy rather than a borrowed pointer because the caller is typically a
 * render thread while [meet_video_effects_process_i420] runs on the capture
 * thread: the copy happens under the engine lock, so the two cannot tear.
 *
 * [out_width] and [out_height] are filled in whenever a frame exists, including
 * when [dst] is NULL, so a caller can size its buffer before asking for pixels.
 * Returns false when nothing has been composed yet or [dst_capacity] is too
 * small for width*height*4 bytes.
 */
bool meet_video_effects_copy_last_frame_rgba(MeetVideoEffectsEngine* engine,
                                             uint8_t* dst,
                                             size_t dst_capacity,
                                             int* out_width,
                                             int* out_height);

#ifdef __cplusplus
}
#endif

#endif  // MEET_VIDEO_EFFECTS_H_
