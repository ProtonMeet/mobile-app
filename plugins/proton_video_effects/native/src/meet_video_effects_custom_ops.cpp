/*
 * Copyright (c) 2026 Proton AG
 *
 * `Convolution2DTransposeBias` — a transposed convolution that folds its bias
 * in, used by MediaPipe's selfie segmentation models.
 *
 * Ported from MediaPipe's mediapipe/util/tflite/operations/transpose_conv_bias.cc
 * (Apache License 2.0; Copyright 2018 The TensorFlow Authors, Copyright 2019
 * The MediaPipe Authors). Reworked against TensorFlow Lite's opaque C API
 * because this plugin links the C shared library, not the C++ one, so the
 * TfLiteTensor / TfLiteContext types the original uses are not visible here.
 */

#include "meet_video_effects_custom_ops.h"

// The engine compiles its segmentation paths out when TFLite is unavailable, so
// this translation unit has to do the same rather than reach for TFLite headers
// that are not on the include path.
#ifdef MEET_VIDEO_EFFECTS_USE_TFLITE

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstring>

#include "tensorflow/lite/c/builtin_op_data.h"
#include "tensorflow/lite/c/c_api.h"
#include "tensorflow/lite/c/c_api_opaque.h"
#include "tensorflow/lite/c/common.h"

namespace meet_video_effects {
namespace {

constexpr int kInputTensor = 0;
constexpr int kWeightsTensor = 1;
constexpr int kBiasTensor = 2;

/// Mirrors the `TfLiteTransposeConvParams` prefix that the model's custom
/// options are serialized as: three int32s, `{padding, stride_w, stride_h}`.
/// `TfLitePadding` is `kTfLitePaddingUnknown/Same/Valid` = 0/1/2.
struct TransposeConvBiasParams {
  int32_t padding;
  int32_t stride_width;
  int32_t stride_height;
};

/// The custom options are a raw struct rather than a flexbuffer, which is what
/// MediaPipe assumes too. That assumption is worth checking rather than
/// trusting, so every field is range-checked before use.
bool ReadParams(TfLiteOpaqueContext* context,
                const TfLiteOpaqueNode* node,
                TransposeConvBiasParams* out) {
  const void* data = nullptr;
  int size = 0;
  if (TfLiteOpaqueNodeGetCustomInitialData(node, &data, &size) != kTfLiteOk ||
      data == nullptr || size < static_cast<int>(sizeof(*out))) {
    TfLiteOpaqueContextReportError(
        context, "Convolution2DTransposeBias: custom options are %d bytes, need %d.",
        size, static_cast<int>(sizeof(*out)));
    return false;
  }
  TransposeConvBiasParams params{};
  std::memcpy(&params, data, sizeof(params));
  const bool padding_ok = params.padding == kTfLitePaddingSame ||
                          params.padding == kTfLitePaddingValid;
  const bool stride_ok = params.stride_width > 0 && params.stride_width <= 64 &&
                         params.stride_height > 0 && params.stride_height <= 64;
  if (!padding_ok || !stride_ok) {
    TfLiteOpaqueContextReportError(
        context,
        "Convolution2DTransposeBias: implausible options "
        "(padding=%d stride=%dx%d); the model may not encode them as a raw struct.",
        params.padding, params.stride_width, params.stride_height);
    return false;
  }
  *out = params;
  return true;
}

/// Total padding SAME mode implies. Halved before use, matching MediaPipe.
void ComputePadding(const TransposeConvBiasParams& params,
                    int in_height, int in_width,
                    int filter_height, int filter_width,
                    int* pad_height, int* pad_width) {
  if (params.padding != kTfLitePaddingSame) {
    *pad_height = 0;
    *pad_width = 0;
    return;
  }
  *pad_height = std::max(
      0, filter_height - (in_height - 1) % params.stride_height - 1);
  *pad_width =
      std::max(0, filter_width - (in_width - 1) % params.stride_width - 1);
}

bool IsFloat32(const TfLiteOpaqueTensor* tensor) {
  return tensor != nullptr && TfLiteOpaqueTensorType(tensor) == kTfLiteFloat32;
}

TfLiteStatus Prepare(TfLiteOpaqueContext* context, TfLiteOpaqueNode* node) {
  if (TfLiteOpaqueNodeNumberOfInputs(node) != 3 ||
      TfLiteOpaqueNodeNumberOfOutputs(node) != 1) {
    TfLiteOpaqueContextReportError(
        context, "Convolution2DTransposeBias: expected 3 inputs and 1 output.");
    return kTfLiteError;
  }

  const TfLiteOpaqueTensor* input =
      TfLiteOpaqueNodeGetInput(context, node, kInputTensor);
  const TfLiteOpaqueTensor* weights =
      TfLiteOpaqueNodeGetInput(context, node, kWeightsTensor);
  const TfLiteOpaqueTensor* bias =
      TfLiteOpaqueNodeGetInput(context, node, kBiasTensor);
  TfLiteOpaqueTensor* output = TfLiteOpaqueNodeGetOutput(context, node, 0);
  if (!input || !weights || !bias || !output) return kTfLiteError;

  if (!IsFloat32(input) || !IsFloat32(weights) || !IsFloat32(bias) ||
      !IsFloat32(output)) {
    TfLiteOpaqueContextReportError(
        context, "Convolution2DTransposeBias: only float32 is supported.");
    return kTfLiteError;
  }
  if (TfLiteOpaqueTensorNumDims(input) != 4 ||
      TfLiteOpaqueTensorNumDims(weights) != 4 ||
      TfLiteOpaqueTensorNumDims(bias) != 1) {
    TfLiteOpaqueContextReportError(
        context, "Convolution2DTransposeBias: expected 4D input/weights and 1D bias.");
    return kTfLiteError;
  }
  // Weights are OHWI, so dim 3 pairs with the input channels and dim 0 with the
  // bias and output channels.
  if (TfLiteOpaqueTensorDim(weights, 3) != TfLiteOpaqueTensorDim(input, 3) ||
      TfLiteOpaqueTensorDim(weights, 0) != TfLiteOpaqueTensorDim(bias, 0)) {
    TfLiteOpaqueContextReportError(
        context, "Convolution2DTransposeBias: weights do not match input/bias channels.");
    return kTfLiteError;
  }

  TransposeConvBiasParams params{};
  if (!ReadParams(context, node, &params)) return kTfLiteError;

  const int in_height = TfLiteOpaqueTensorDim(input, 1);
  const int in_width = TfLiteOpaqueTensorDim(input, 2);
  const int filter_height = TfLiteOpaqueTensorDim(weights, 1);
  const int filter_width = TfLiteOpaqueTensorDim(weights, 2);
  int pad_height = 0, pad_width = 0;
  ComputePadding(params, in_height, in_width, filter_height, filter_width,
                 &pad_height, &pad_width);

  TfLiteIntArray* output_shape = TfLiteIntArrayCreate(4);
  output_shape->data[0] = TfLiteOpaqueTensorDim(input, 0);
  output_shape->data[1] =
      params.stride_height * (in_height - 1) + filter_height - pad_height;
  output_shape->data[2] =
      params.stride_width * (in_width - 1) + filter_width - pad_width;
  output_shape->data[3] = TfLiteOpaqueTensorDim(weights, 0);
  // Ownership of output_shape transfers to TFLite, which frees it inside the
  // same module that allocated it.
  return TfLiteOpaqueContextResizeTensor(context, output, output_shape);
}

TfLiteStatus Invoke(TfLiteOpaqueContext* context, TfLiteOpaqueNode* node) {
  const TfLiteOpaqueTensor* input =
      TfLiteOpaqueNodeGetInput(context, node, kInputTensor);
  const TfLiteOpaqueTensor* weights =
      TfLiteOpaqueNodeGetInput(context, node, kWeightsTensor);
  const TfLiteOpaqueTensor* bias =
      TfLiteOpaqueNodeGetInput(context, node, kBiasTensor);
  TfLiteOpaqueTensor* output = TfLiteOpaqueNodeGetOutput(context, node, 0);
  if (!input || !weights || !bias || !output) return kTfLiteError;

  TransposeConvBiasParams params{};
  if (!ReadParams(context, node, &params)) return kTfLiteError;

  const int batches = TfLiteOpaqueTensorDim(input, 0);
  const int in_height = TfLiteOpaqueTensorDim(input, 1);
  const int in_width = TfLiteOpaqueTensorDim(input, 2);
  const int in_depth = TfLiteOpaqueTensorDim(input, 3);
  const int filter_height = TfLiteOpaqueTensorDim(weights, 1);
  const int filter_width = TfLiteOpaqueTensorDim(weights, 2);
  const int out_height = TfLiteOpaqueTensorDim(output, 1);
  const int out_width = TfLiteOpaqueTensorDim(output, 2);
  const int out_depth = TfLiteOpaqueTensorDim(output, 3);

  int pad_height = 0, pad_width = 0;
  ComputePadding(params, in_height, in_width, filter_height, filter_width,
                 &pad_height, &pad_width);
  // MediaPipe splits the SAME padding evenly across both edges.
  pad_height /= 2;
  pad_width /= 2;

  const auto* input_data =
      static_cast<const float*>(TfLiteOpaqueTensorData(input));
  const auto* filter_data =
      static_cast<const float*>(TfLiteOpaqueTensorData(weights));
  const auto* bias_data =
      static_cast<const float*>(TfLiteOpaqueTensorData(bias));
  auto* output_data = static_cast<float*>(TfLiteOpaqueTensorData(output));
  if (!input_data || !filter_data || !bias_data || !output_data) {
    return kTfLiteError;
  }

  for (int batch = 0; batch < batches; ++batch) {
    float* out_batch =
        output_data + static_cast<ptrdiff_t>(batch) * out_height * out_width * out_depth;

    // Seed with the bias, then scatter-accumulate the convolution on top.
    for (int i = 0; i < out_height * out_width; ++i) {
      std::copy(bias_data, bias_data + out_depth, out_batch + static_cast<ptrdiff_t>(i) * out_depth);
    }

    const float* in_batch =
        input_data + static_cast<ptrdiff_t>(batch) * in_height * in_width * in_depth;
    for (int in_y = 0; in_y < in_height; ++in_y) {
      for (int in_x = 0; in_x < in_width; ++in_x) {
        const int out_y_origin = in_y * params.stride_height - pad_height;
        const int out_x_origin = in_x * params.stride_width - pad_width;
        const float* in_pixel =
            in_batch + (static_cast<ptrdiff_t>(in_y) * in_width + in_x) * in_depth;

        for (int filter_y = 0; filter_y < filter_height; ++filter_y) {
          const int out_y = out_y_origin + filter_y;
          if (out_y < 0 || out_y >= out_height) continue;
          for (int filter_x = 0; filter_x < filter_width; ++filter_x) {
            const int out_x = out_x_origin + filter_x;
            if (out_x < 0 || out_x >= out_width) continue;

            float* out_pixel =
                out_batch + (static_cast<ptrdiff_t>(out_y) * out_width + out_x) * out_depth;
            for (int in_c = 0; in_c < in_depth; ++in_c) {
              const float input_value = in_pixel[in_c];
              if (input_value == 0.f) continue;
              // Filter is OHWI: stepping out_channel strides a whole HWI plane.
              const float* tap = filter_data +
                                 (static_cast<ptrdiff_t>(filter_y) * filter_width + filter_x) *
                                     in_depth +
                                 in_c;
              const ptrdiff_t tap_stride =
                  static_cast<ptrdiff_t>(filter_height) * filter_width * in_depth;
              for (int out_c = 0; out_c < out_depth; ++out_c) {
                out_pixel[out_c] += input_value * tap[out_c * tap_stride];
              }
            }
          }
        }
      }
    }
  }
  return kTfLiteOk;
}

}  // namespace

bool RegisterCustomOps(TfLiteInterpreterOptions* options) {
  if (!options) return false;
  // Stateless and shared for the process; TFLite requires the operator to
  // outlive every interpreter built from these options.
  static TfLiteOperator* op = [] {
    TfLiteOperator* created = TfLiteOperatorCreate(
        kTfLiteBuiltinCustom, "Convolution2DTransposeBias", /*version=*/1);
    if (created) {
      TfLiteOperatorSetPrepare(created, Prepare);
      TfLiteOperatorSetInvoke(created, Invoke);
    }
    return created;
  }();
  if (!op) return false;
  TfLiteInterpreterOptionsAddOperator(options, op);
  return true;
}

}  // namespace meet_video_effects

#else  // !MEET_VIDEO_EFFECTS_USE_TFLITE

namespace meet_video_effects {

bool RegisterCustomOps(TfLiteInterpreterOptions* /*options*/) { return false; }

}  // namespace meet_video_effects

#endif  // MEET_VIDEO_EFFECTS_USE_TFLITE
