#!/usr/bin/env bash
# Build TensorFlow Lite for Linux/macOS/desktop CPU (XNNPACK). Adjust for Windows in CI.
set -euo pipefail

TFLITE_TAG="${TFLITE_TAG:-v2.17.0}"
BUILD_DIR="${BUILD_DIR:-$(pwd)/../../build/tflite-desktop}"

if [[ ! -d "${BUILD_DIR}/tensorflow-lite" ]]; then
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  git clone --depth 1 --branch "${TFLITE_TAG}" https://github.com/tensorflow/tensorflow.git "$WORK/tf"
  cmake -S "$WORK/tf/tensorflow/lite" -B "${BUILD_DIR}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DTFLITE_ENABLE_XNNPACK=ON \
    -DTFLITE_ENABLE_GPU=OFF
fi

cmake --build "${BUILD_DIR}" -j"$(sysctl -n hw.ncpu 2>/dev/null || nproc)"

echo ""
echo "Done. Build with:"
echo "  flutter build linux --cmake-args=\"-DTFLITE_ROOT=${BUILD_DIR}\""
