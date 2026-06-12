#!/usr/bin/env bash
# Build dtln-rs static libraries into plugins/proton_denoise/third_party/dtln-rs/lib/.
#
# Usage:
#   ./plugins/proton_denoise/scripts/dtln/build-dtln-rs.sh [all|apple|macos|ios|android|source|install-check]
#
# Builds copy directly into plugins/proton_denoise/third_party/dtln-rs/lib/ (no manual step).
#
# macos / ios / apple use fat (lipo) universal libs by default.
# Per-arch thin slices: build-dtln-rs-apple.sh <platform> <arch>
#
# Environment (optional):
#   DTLN_RS_SRC          — upstream git checkout (default: .local/dtln-rs-src)
#   DTLN_RS_GIT_URL      — default https://github.com/DataDog/dtln-rs.git
#   DTLN_RS_GIT_REF      — default master
#   DTLN_RS_TFLITE_LIB_DIR — Android: directory with libtensorflow-lite.a (runtime)
#   Android: one merged libdtln.a per ABI (~40 MB/arm64), same as iOS packaging
#   DTLN_RS_CARGO_PROFILE — release (default) or debug
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=build-dtln-rs-env.sh
source "${SCRIPT_DIR}/build-dtln-rs-env.sh"

usage() {
  sed -n '2,12p' "$0" >&2
  exit 1
}

MODE="${1:-all}"

run_apple_fat() {
  bash "${SCRIPT_DIR}/build-dtln-rs-apple-fat.sh" all
}

run_android_matrix() {
  dtln_rs_resolve_rust
  dtln_rs_prepare_build_tree
  export DTLN_RS_SKIP_PREPARE=1
  local abi
  for abi in armeabi-v7a arm64-v8a x86_64; do
    echo "=== dtln-rs android ${abi} ==="
    bash "${SCRIPT_DIR}/build-dtln-rs-android.sh" "${abi}"
  done
  unset DTLN_RS_SKIP_PREPARE
}

case "${MODE}" in
  source)
    dtln_rs_ensure_source
    echo "dtln-rs source ready at ${DTLN_RS_SRC}"
    ;;
  macos)
    bash "${SCRIPT_DIR}/build-dtln-rs-apple-fat.sh" macos
    ;;
  ios)
    bash "${SCRIPT_DIR}/build-dtln-rs-apple-fat.sh" ios
    ;;
  apple | apple-fat)
    run_apple_fat
    ;;
  android)
    run_android_matrix
    dtln_rs_finalize_third_party_install
    ;;
  all)
    run_apple_fat
    run_android_matrix || echo "dtln-rs: android skipped or failed (needs DTLN_RS_TFLITE_LIB_DIR)" >&2
    dtln_rs_finalize_third_party_install
    ;;
  install-check)
    dtln_rs_finalize_third_party_install
    ;;
  *)
    usage
    ;;
esac
