#!/usr/bin/env bash
# Cross-compile libdeepfilter.so for one Android ABI (Meet: armeabi-v7a, arm64-v8a, x86_64).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=build-deepfilter-env.sh
source "${SCRIPT_DIR}/build-deepfilter-env.sh"
# shellcheck source=../dtln/build-dtln-rs-env.sh
source "${SCRIPT_DIR}/../dtln/build-dtln-rs-env.sh"

usage() {
  cat <<'EOF' >&2
Usage: build-deepfilter-android.sh <abi> [output_libdeepfilter.so]

  abi   armeabi-v7a | arm64-v8a | x86_64

Produces libdeepfilter.so (cdylib from libDF) into
plugins/proton_denoise/third_party/deepfilter/lib/android/<abi>/.
EOF
  exit 1
}

ABI="${1:-}"
OUT="${2:-}"
[[ -n "${ABI}" ]] || usage

deepfilter_resolve_rust
deepfilter_ensure_sources
# Prefer Meet NDK from android/local.properties over a stale ANDROID_NDK_HOME.
unset ANDROID_NDK_HOME
dtln_rs_resolve_ndk
dtln_rs_android_ndk_env "${ABI}"

OUT="${OUT:-$(deepfilter_android_abi_out "${ABI}")}"
deepfilter_build_android_abi "${ABI}" "${OUT}"
