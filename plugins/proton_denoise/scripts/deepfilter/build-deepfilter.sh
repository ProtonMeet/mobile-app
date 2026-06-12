#!/usr/bin/env bash
# Build DeepFilterNet libdf for iOS device (default), Android, or other targets.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TARGET="${1:-ios}"

case "${TARGET}" in
  ios)
    sh "${SCRIPT_DIR}/build-deepfilter-apple.sh" iphoneos arm64
    ;;
  ios-sim)
    for arch in arm64 x86_64; do
      sh "${SCRIPT_DIR}/build-deepfilter-apple.sh" iphonesimulator "${arch}"
    done
    ;;
  macos)
    bash "${SCRIPT_DIR}/build-deepfilter-macos-fat.sh"
    ;;
  android)
    for abi in armeabi-v7a arm64-v8a x86_64; do
      bash "${SCRIPT_DIR}/build-deepfilter-android.sh" "${abi}"
    done
    ;;
  android-arm64)
    bash "${SCRIPT_DIR}/build-deepfilter-android.sh" arm64-v8a
    ;;
  *)
    echo "Usage: build-deepfilter.sh [ios|ios-sim|macos|android|android-arm64]" >&2
    echo "  macos — universal DeepFilter.framework (arm64 + x86_64)" >&2
    exit 1
    ;;
esac
