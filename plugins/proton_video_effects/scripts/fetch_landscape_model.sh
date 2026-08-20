#!/usr/bin/env bash
# Download MediaPipe landscape selfie segmenter (Google Meet variant, 144×256).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "${ROOT}/../.." && pwd)"
PLUGIN_CACHE_REPO_ROOT="${REPO_ROOT}"
export PLUGIN_CACHE_REPO_ROOT
# shellcheck source=../../../scripts/plugin_cache.sh
. "${REPO_ROOT}/scripts/plugin_cache.sh"

MODEL_NAME="selfie_segmenter_landscape.tflite"
URL="https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_segmenter_landscape/float16/latest/${MODEL_NAME}"
DEST_ANDROID="${ROOT}/android/src/main/assets/${MODEL_NAME}"
DEST_IOS="${ROOT}/ios/Resources/${MODEL_NAME}"
CACHE_MODEL=$(plugin_cache_download_path "models/${MODEL_NAME}")

mkdir -p "$(dirname "${DEST_ANDROID}")" "$(dirname "${DEST_IOS}")"

if [ -f "${CACHE_MODEL}" ]; then
  echo "fetch_landscape_model: using plugin-cache ${CACHE_MODEL}"
  cp -f "${CACHE_MODEL}" "${DEST_ANDROID}"
else
  cached=$(plugin_cache_ensure_download "models/${MODEL_NAME}" "${URL}")
  cp -f "${cached}" "${DEST_ANDROID}"
fi

cp -f "${DEST_ANDROID}" "${DEST_IOS}"
ls -la "${DEST_ANDROID}" "${DEST_IOS}"
