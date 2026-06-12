#!/usr/bin/env bash
# Build libdf.a for one Apple SDK/arch slice.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=build-deepfilter-env.sh
source "${SCRIPT_DIR}/build-deepfilter-env.sh"

usage() {
  cat <<'EOF' >&2
Usage: build-deepfilter-apple.sh <platform> <arch> [output_libdf.a]

  platform   iphoneos | iphonesimulator | macosx
  arch       arm64 | x86_64
EOF
  exit 1
}

PLATFORM="${1:-}"
ARCH="${2:-}"
OUT="${3:-}"

[[ -n "${PLATFORM}" && -n "${ARCH}" ]] || usage

deepfilter_resolve_rust
deepfilter_ensure_sources
mkdir -p "${DEEPFILTER_APPLE_STAGING}"

if [[ -z "${OUT}" ]]; then
  case "${PLATFORM}" in
    macosx)
      OUT="$(deepfilter_macos_slice_out "${ARCH}")"
      ;;
    iphoneos | iphonesimulator)
      OUT="$(deepfilter_ios_slice_out "${PLATFORM}" "${ARCH}")"
      ;;
    *)
      usage
      ;;
  esac
fi

deepfilter_build_apple_slice "${PLATFORM}" "${ARCH}" "${OUT}"
