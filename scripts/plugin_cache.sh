#!/bin/sh
# Shared cache helpers for plugin build-time downloads (RNNoise, optional models).
#
# Committed cache: plugins/plugin-cache/downloads/  (Git LFS — see .gitattributes)
# MediaPipe iOS pods are not cached here — use CocoaPods during prepare_ios_spm.sh.
#
# Override: PLUGIN_CACHE_DIR=/path/to/cache
#
# Usage (sourced):
#   . scripts/plugin_cache.sh
#   plugin_cache_download_path rnnoise/rnnoise_data-0b50c45.tar.gz
#   plugin_cache_ensure_download rnnoise/rnnoise_data-0b50c45.tar.gz "$url"
set -eu

plugin_cache_repo_root() {
  if [ -n "${PLUGIN_CACHE_REPO_ROOT:-}" ]; then
    echo "${PLUGIN_CACHE_REPO_ROOT}"
    return 0
  fi
  case "$0" in
    */plugin_cache.sh | */prefetch_plugin_cache.sh)
      cd "$(dirname "$0")/.." && pwd -P
      ;;
    *)
      echo "plugin_cache: set PLUGIN_CACHE_REPO_ROOT before sourcing plugin_cache.sh" >&2
      exit 1
      ;;
  esac
}

plugin_cache_root() {
  if [ -n "${PLUGIN_CACHE_DIR:-}" ]; then
    echo "${PLUGIN_CACHE_DIR}"
    return 0
  fi
  echo "$(plugin_cache_repo_root)/plugins/plugin-cache"
}

plugin_cache_require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "plugin_cache: required command not found: $1" >&2
    exit 1
  fi
}

# Canonical path for a downloaded blob (under downloads/).
plugin_cache_download_path() {
  echo "$(plugin_cache_root)/downloads/$1"
}

# RNNoise upstream source archive for a git tag (e.g. v0.2).
plugin_cache_rnnoise_source_archive() {
  _tag="${1:-v0.2}"
  plugin_cache_download_path "rnnoise/rnnoise-${_tag}.tar.gz"
}

# Ensure downloads/<name> exists; print its path. Network only on cache miss.
plugin_cache_ensure_download() {
  _name="$1"
  _url="$2"
  _cache_file=$(plugin_cache_download_path "${_name}")
  mkdir -p "$(dirname "${_cache_file}")"

  if [ ! -f "${_cache_file}" ]; then
    plugin_cache_require_cmd curl
    echo "plugin_cache: downloading ${_name}" >&2
    curl -fsSL "${_url}" -o "${_cache_file}.partial"
    mv "${_cache_file}.partial" "${_cache_file}"
  else
    echo "plugin_cache: using cached ${_name}" >&2
  fi

  echo "${_cache_file}"
}
