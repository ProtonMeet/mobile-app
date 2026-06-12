#!/usr/bin/env bash
# Build fat (universal) libdeepfilter.dylib for macOS.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=build-deepfilter-env.sh
source "${SCRIPT_DIR}/build-deepfilter-env.sh"

usage() {
  cat <<'EOF' >&2
Usage: build-deepfilter-macos-fat.sh

Builds per-arch slices under .local/deepfilter-staging/apple/macos/, then lipo-merges:

  apple/macos/libdeepfilter.dylib — universal (arm64 + x86_64 by default)

Override arch list:
  DEEPFILTER_MACOS_ARCHS="arm64"    # Apple Silicon–only Mac builds

Single-slice builds still work via build-deepfilter-apple.sh macosx <arch>.
EOF
  exit 1
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage

deepfilter_resolve_rust
deepfilter_ensure_sources
mkdir -p "${DEEPFILTER_STAGING_DIR}"

slices=()
for arch in ${DEEPFILTER_MACOS_ARCHS}; do
  slice_out="$(deepfilter_macos_slice_out "${arch}")"
  echo "=== deepfilter slice macosx ${arch} ==="
  deepfilter_build_apple_slice macosx "${arch}" "${slice_out}"
  slices+=("${slice_out}")
done

fat_out="$(deepfilter_macos_fat_out)"
deepfilter_lipo_fat "${fat_out}" "${slices[@]}"
deepfilter_finalize_macos_install
sh "${SCRIPT_DIR}/package_deepfilter_macos_framework.sh"
