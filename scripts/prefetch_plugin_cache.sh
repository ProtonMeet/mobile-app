#!/bin/sh
# Populate plugins/plugin-cache/ with build-time plugin dependencies.
# Run once (or in CI), commit via Git LFS, then builds use the cache offline.
#
# MediaPipe iOS pods are not cached here — use CocoaPods (`pod install`) instead.
#
# Usage:
#   sh scripts/prefetch_plugin_cache.sh           # fetch anything missing
#   sh scripts/prefetch_plugin_cache.sh --check # exit 1 if cache incomplete
set -eu

export PATH="/opt/homebrew/bin:/usr/local/bin:/Applications/CMake.app/Contents/bin:${PATH}"

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
PLUGIN_CACHE_REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd -P)
export PLUGIN_CACHE_REPO_ROOT
. "${SCRIPT_DIR}/plugin_cache.sh"

CHECK_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --check)
      CHECK_ONLY=1
      shift
      ;;
    -h | --help)
      sed -n '1,10p' "$0"
      exit 0
      ;;
    *)
      echo "prefetch_plugin_cache: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

CACHE=$(plugin_cache_root)
RNNOISE_TAG="${RNNOISE_GIT_TAG:-v0.2}"
MISSING=0

rnnoise_model_version_from_archive() {
  _archive="$1"
  tar -xOf "${_archive}" model_version 2>/dev/null | tr -d '[:space:]'
}

pack_rnnoise_source() {
  _src_dir="$1"
  _archive="$2"
  mkdir -p "$(dirname "${_archive}")"
  tar czf "${_archive}" -C "${_src_dir}" .
}

prefetch_rnnoise() {
  source_archive=$(plugin_cache_rnnoise_source_archive "${RNNOISE_TAG}")
  legacy_src="${CACHE}/rnnoise/${RNNOISE_TAG}/source"

  if [ ! -f "${source_archive}" ]; then
    if [ "${CHECK_ONLY}" -eq 1 ]; then
      echo "prefetch_plugin_cache: missing RNNoise source archive ${source_archive}" >&2
      MISSING=1
      return 0
    fi
    tmp=$(mktemp -d)
    if [ -f "${legacy_src}/include/rnnoise.h" ]; then
      echo "prefetch_plugin_cache: packing legacy RNNoise source into ${source_archive}"
      pack_rnnoise_source "${legacy_src}" "${source_archive}"
      rm -rf "${legacy_src}"
    else
      plugin_cache_require_cmd git
      echo "prefetch_plugin_cache: fetching RNNoise ${RNNOISE_TAG}"
      git clone --depth 1 --branch "${RNNOISE_TAG}" \
        https://github.com/xiph/rnnoise.git "${tmp}/source"
      pack_rnnoise_source "${tmp}/source" "${source_archive}"
      rm -rf "${tmp}"
    fi
  elif [ -d "${legacy_src}" ]; then
    echo "prefetch_plugin_cache: removing legacy unpacked RNNoise source ${legacy_src}"
    rm -rf "${legacy_src}"
  fi

  model_version=$(rnnoise_model_version_from_archive "${source_archive}")
  if [ -z "${model_version}" ]; then
    echo "prefetch_plugin_cache: could not read model_version from ${source_archive}" >&2
    MISSING=1
    return 0
  fi

  model_tar="rnnoise_data-${model_version}.tar.gz"
  model_cache=$(plugin_cache_download_path "rnnoise/${model_tar}")
  model_url="https://media.xiph.org/rnnoise/models/${model_tar}"

  if [ ! -f "${model_cache}" ]; then
    if [ "${CHECK_ONLY}" -eq 1 ]; then
      echo "prefetch_plugin_cache: missing RNNoise model ${model_cache}" >&2
      MISSING=1
      return 0
    fi
    plugin_cache_ensure_download "rnnoise/${model_tar}" "${model_url}" >/dev/null
  fi
}

prefetch_landscape_model() {
  model_name="selfie_segmenter_landscape.tflite"
  dest=$(plugin_cache_download_path "models/${model_name}")
  url="https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_segmenter_landscape/float16/latest/${model_name}"

  if [ -f "${dest}" ]; then
    return 0
  fi
  if [ "${CHECK_ONLY}" -eq 1 ]; then
    echo "prefetch_plugin_cache: missing model ${dest}" >&2
    MISSING=1
    return 0
  fi
  plugin_cache_ensure_download "models/${model_name}" "${url}" >/dev/null
}

prefetch_rnnoise
prefetch_landscape_model

if [ "${CHECK_ONLY}" -eq 1 ] && [ "${MISSING}" -ne 0 ]; then
  echo "prefetch_plugin_cache: cache incomplete — run: sh scripts/prefetch_plugin_cache.sh" >&2
  exit 1
fi

echo "prefetch_plugin_cache: done (${CACHE})"
