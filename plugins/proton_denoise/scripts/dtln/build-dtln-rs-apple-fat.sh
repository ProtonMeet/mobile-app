#!/usr/bin/env bash
# Build fat (universal) libdtln.a for macOS and iOS Simulator; thin lib for iOS device.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=build-dtln-rs-env.sh
source "${SCRIPT_DIR}/build-dtln-rs-env.sh"

usage() {
  cat <<'EOF' >&2
Usage: build-dtln-rs-apple-fat.sh [macos|ios|all]

Builds per-arch slices under .local/dtln-rs-staging/, then lipo-merges:

  macos/libdtln.a              — universal (arm64 + x86_64 by default)
  ios/device/libdtln.a         — arm64 (iphoneos)
  ios/simulator/libdtln.a      — simulator (arm64 by default on Apple Silicon)
  ios/*/libdtln_tflite.a       — TFLite runtime (separate from Rust libdtln.a)

Override arch lists:
  DTLN_RS_MACOS_ARCHS="arm64"           # Apple Silicon–only Mac builds
  DTLN_RS_IOS_SIM_ARCHS="arm64 x86_64"  # universal simulator (Intel Mac / CI)

Single-slice (non-fat) builds still work via build-dtln-rs-apple.sh.
EOF
  exit 1
}

build_macos_fat() {
  local arch slice_out slices=()
  for arch in ${DTLN_RS_MACOS_ARCHS}; do
    slice_out="${DTLN_RS_STAGING_DIR}/macos/${arch}/libdtln.a"
    echo "=== dtln-rs slice macosx ${arch} ==="
    dtln_rs_build_apple_slice macosx "${arch}" "${slice_out}"
    slices+=("${slice_out}")
  done
  dtln_rs_lipo_fat "${DTLN_RS_LIB_OUT}/macos/libdtln.a" "${slices[@]}"
  rm -f "${DTLN_RS_LIB_OUT}/macos/libdtln_tflite.a"
}

build_ios_fat() {
  local arch slice_out tflite_slice slices=() tflite_slices=()

  slice_out="${DTLN_RS_STAGING_DIR}/ios/device-arm64/libdtln.a"
  echo "=== dtln-rs slice iphoneos arm64 ==="
  dtln_rs_build_apple_slice iphoneos arm64 "${slice_out}"
  dtln_rs_lipo_fat "${DTLN_RS_LIB_OUT}/ios/device/libdtln.a" "${slice_out}"
  tflite_slice="$(dirname "${slice_out}")/libdtln_tflite.a"
  if [[ -f "${tflite_slice}" ]]; then
    dtln_rs_install_lib "${DTLN_RS_LIB_OUT}/ios/device/libdtln_tflite.a" "${tflite_slice}"
  else
    echo "dtln-rs: missing ${tflite_slice}" >&2
    return 1
  fi

  slices=()
  tflite_slices=()
  for arch in ${DTLN_RS_IOS_SIM_ARCHS}; do
    slice_out="${DTLN_RS_STAGING_DIR}/ios/simulator-${arch}/libdtln.a"
    echo "=== dtln-rs slice iphonesimulator ${arch} ==="
    dtln_rs_build_apple_slice iphonesimulator "${arch}" "${slice_out}"
    slices+=("${slice_out}")
    tflite_slice="$(dirname "${slice_out}")/libdtln_tflite.a"
    if [[ -f "${tflite_slice}" ]]; then
      tflite_slices+=("${tflite_slice}")
    else
      echo "dtln-rs: missing ${tflite_slice}" >&2
      return 1
    fi
  done
  dtln_rs_lipo_fat "${DTLN_RS_LIB_OUT}/ios/simulator/libdtln.a" "${slices[@]}"
  dtln_rs_lipo_fat "${DTLN_RS_LIB_OUT}/ios/simulator/libdtln_tflite.a" "${tflite_slices[@]}"

  local verify="${SCRIPT_DIR}/verify_dtln_apple_lib.sh"
  sh "${verify}" iphoneos "${DTLN_RS_LIB_OUT}/ios/device/libdtln.a"
  sh "${verify}" iphoneos "${DTLN_RS_LIB_OUT}/ios/device/libdtln_tflite.a"
  sh "${verify}" iphonesimulator "${DTLN_RS_LIB_OUT}/ios/simulator/libdtln.a"
  sh "${verify}" iphonesimulator "${DTLN_RS_LIB_OUT}/ios/simulator/libdtln_tflite.a"
  echo "dtln-rs: iOS prebuilts verified under ${DTLN_RS_LIB_OUT}/ios"
}

MODE="${1:-all}"

dtln_rs_resolve_rust
dtln_rs_prepare_build_tree
mkdir -p "${DTLN_RS_STAGING_DIR}"

case "${MODE}" in
  macos)
    build_macos_fat
    dtln_rs_finalize_third_party_install "${DTLN_RS_LIB_OUT}/macos/libdtln.a"
    ;;
  ios)
    build_ios_fat
    dtln_rs_finalize_third_party_install \
      "${DTLN_RS_LIB_OUT}/ios/device/libdtln.a" \
      "${DTLN_RS_LIB_OUT}/ios/simulator/libdtln.a"
    ;;
  all)
    build_macos_fat
    build_ios_fat
    dtln_rs_finalize_third_party_install \
      "${DTLN_RS_LIB_OUT}/macos/libdtln.a" \
      "${DTLN_RS_LIB_OUT}/ios/device/libdtln.a" \
      "${DTLN_RS_LIB_OUT}/ios/simulator/libdtln.a"
    echo "dtln-rs: Apple libraries copied to ${DTLN_RS_LIB_OUT}/{macos,ios}"
    ;;
  *)
    usage
    ;;
esac
