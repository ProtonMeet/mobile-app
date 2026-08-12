#!/bin/sh
# Stage SwiftPM binary inputs for proton_denoise and proton_video_effects.
#
# The xcframeworks live under each plugin package and are gitignored. Flutter resolves
# SwiftPM packages before xcodebuild, so they must exist before `flutter build ios|ipa|macos`.
#
# Usage:
#   sh scripts/prepare_apple_spm.sh            # ios + macos (denoise only on macos)
#   sh scripts/prepare_apple_spm.sh ios
#   sh scripts/prepare_apple_spm.sh macos
#   sh scripts/prepare_apple_spm.sh --if-needed ios   # skip when already staged
set -eu

export PATH="/opt/homebrew/bin:/usr/local/bin:/Applications/CMake.app/Contents/bin:${PATH}"

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd -P)

IF_NEEDED=0
PLATFORMS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --if-needed)
      IF_NEEDED=1
      shift
      ;;
    ios | macos | all)
      PLATFORMS="${PLATFORMS} $1"
      shift
      ;;
    -h | --help)
      sed -n '1,12p' "$0"
      exit 0
      ;;
    *)
      echo "prepare_apple_spm: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ -z "${PLATFORMS}" ]; then
  PLATFORMS=" all"
fi

ios_staged() {
  test -d "${REPO_ROOT}/plugins/proton_denoise/ios/proton_denoise/VendoredFrameworks/RNNoise.xcframework" &&
    test -d "${REPO_ROOT}/plugins/proton_video_effects/ios/proton_video_effects/VendoredFrameworks/MediaPipeTasksCommon.xcframework"
}

macos_staged() {
  test -d "${REPO_ROOT}/plugins/proton_denoise/macos/proton_denoise/VendoredFrameworks/RNNoise.xcframework"
}

prepare_ios() {
  if [ "${IF_NEEDED}" -eq 1 ] && ios_staged; then
    echo "prepare_apple_spm: iOS inputs already staged — skipping"
    return 0
  fi
  sh "${REPO_ROOT}/plugins/proton_denoise/scripts/spm/prepare_ios_spm.sh"
  sh "${REPO_ROOT}/plugins/proton_video_effects/scripts/spm/prepare_ios_spm.sh"
}

prepare_macos() {
  if [ "${IF_NEEDED}" -eq 1 ] && macos_staged; then
    echo "prepare_apple_spm: macOS inputs already staged — skipping"
    return 0
  fi
  sh "${REPO_ROOT}/plugins/proton_denoise/scripts/spm/prepare_macos_spm.sh"
}

for platform in ${PLATFORMS}; do
  case "${platform}" in
    ios)
      prepare_ios
      ;;
    macos)
      prepare_macos
      ;;
    all)
      prepare_ios
      prepare_macos
      ;;
  esac
done
