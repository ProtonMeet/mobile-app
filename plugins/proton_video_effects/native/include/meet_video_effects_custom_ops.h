/*
 * Copyright (c) 2026 Proton AG
 * Custom TensorFlow Lite operators required by the bundled segmentation models.
 */

#ifndef MEET_VIDEO_EFFECTS_CUSTOM_OPS_H_
#define MEET_VIDEO_EFFECTS_CUSTOM_OPS_H_

typedef struct TfLiteInterpreterOptions TfLiteInterpreterOptions;

namespace meet_video_effects {

/**
 * Registers `Convolution2DTransposeBias` on [options].
 *
 * `selfie_segmenter.tflite` is a MediaPipe model and uses this one operator,
 * which stock TensorFlow Lite does not implement. MediaPipe registers it on
 * iOS/Android; on desktop we link plain TFLite, so without this the model fails
 * to load with "Encountered unresolved custom op".
 *
 * Must be called before the interpreter is created. Returns false if the
 * operator could not be created.
 */
bool RegisterCustomOps(TfLiteInterpreterOptions* options);

}  // namespace meet_video_effects

#endif  // MEET_VIDEO_EFFECTS_CUSTOM_OPS_H_
