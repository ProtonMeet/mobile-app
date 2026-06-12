#!/usr/bin/env bash
# Build libdtln.a for one Apple SDK/arch (thin slice). For universal libs use build-dtln-rs-apple-fat.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=build-dtln-rs-env.sh
source "${SCRIPT_DIR}/build-dtln-rs-env.sh"

usage() {
  cat <<'EOF' >&2
Usage: build-dtln-rs-apple.sh <platform> <arch> [output_libdtln.a]

  platform   macosx | iphoneos | iphonesimulator
  arch       arm64 | x86_64

Fat/universal builds (recommended for Meet):
  build-dtln-rs-apple-fat.sh [macos|ios|all]
EOF
  exit 1
}

PLATFORM="${1:-}"
ARCH="${2:-}"
OUT="${3:-}"

[[ -n "${PLATFORM}" && -n "${ARCH}" ]] || usage

dtln_rs_resolve_rust
dtln_rs_prepare_build_tree

if [[ -z "${OUT}" ]]; then
  case "${PLATFORM}:${ARCH}" in
    macosx:*)
      OUT="${DTLN_RS_LIB_OUT}/macos/${ARCH}/libdtln.a"
      ;;
    iphoneos:*)
      OUT="${DTLN_RS_LIB_OUT}/ios/device-${ARCH}/libdtln.a"
      ;;
    iphonesimulator:*)
      OUT="${DTLN_RS_LIB_OUT}/ios/simulator-${ARCH}/libdtln.a"
      ;;
    *)
      usage
      ;;
  esac
fi

dtln_rs_build_apple_slice "${PLATFORM}" "${ARCH}" "${OUT}"
