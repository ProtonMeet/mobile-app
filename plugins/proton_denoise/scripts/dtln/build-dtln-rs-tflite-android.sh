#!/usr/bin/env bash
# Build TensorFlow Lite static libs for one Android ABI (cached under .local/).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=build-dtln-rs-env.sh
source "${SCRIPT_DIR}/build-dtln-rs-env.sh"

ABI="${1:-}"
[[ -n "${ABI}" ]] || {
  echo "Usage: build-dtln-rs-tflite-android.sh <armeabi-v7a|arm64-v8a|x86_64>" >&2
  exit 1
}

dtln_rs_build_tflite_android "${ABI}"
