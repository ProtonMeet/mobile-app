#!/bin/sh
# Stage the binary inputs of the macos/proton_denoise Swift package.
#
# SwiftPM binary targets only accept xcframeworks and, unlike CocoaPods, cannot run a
# build phase, so the vendored archives have to be wrapped up front.
#
# Usage: sh plugins/proton_denoise/scripts/spm/prepare_macos_spm.sh
set -eu

export PATH="/opt/homebrew/bin:/usr/local/bin:/Applications/CMake.app/Contents/bin:${PATH}"

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
PLUGIN_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd -P)
PACKAGE_DIR="${PLUGIN_ROOT}/macos/proton_denoise"
OUT_DIR="${PACKAGE_DIR}/VendoredFrameworks"
RESOURCE_DIR="${PACKAGE_DIR}/Sources/proton_denoise/Resources"
RNNOISE_LIB="${PLUGIN_ROOT}/third_party/rnnoise/lib/macos/librnnoise.a"
DTLN_LIB="${PLUGIN_ROOT}/third_party/dtln-rs/lib/macos/libdtln.a"
DEEPFILTER_FW="${PLUGIN_ROOT}/third_party/deepfilter/macos/DeepFilter.framework"
DEEPFILTER_MODEL="${PLUGIN_ROOT}/third_party/deepfilter/models/DeepFilterNet3_onnx.tar.gz"

CONFIGURATION="${CONFIGURATION:-Release}"
export CONFIGURATION

mkdir -p "${OUT_DIR}"

has_arch() {
  lipo -archs "$1" 2>/dev/null | tr ' ' '\n' | grep -qx "$2"
}

# RNNoise is built from source and gitignored (CocoaPods did this in a script phase). It has to
# come out universal like the vendored dtln/DeepFilter binaries: SwiftPM bakes the archive in at
# staging time, so a host-only build would fail to link an Intel or universal app.
if ! has_arch "${RNNOISE_LIB}" arm64 || ! has_arch "${RNNOISE_LIB}" x86_64; then
  PLATFORM_NAME=macosx ARCHS="arm64 x86_64" \
    sh "${PLUGIN_ROOT}/scripts/rnnoise/build_rnnoise.sh" apple "${RNNOISE_LIB}"
fi

# The macOS archives are already fat (arm64 + x86_64), so each xcframework holds one slice.
# Unlike iOS, dtln-rs needs no symbol hiding here: it links its own TensorFlow Lite and macOS
# has no MediaPipe (proton_video_effects falls back to Vision) to collide with.
stage_xcframework() {
  name="$1"
  kind="$2"
  path="$3"
  rm -rf "${OUT_DIR}/${name}.xcframework"
  if [ ! -e "${path}" ]; then
    echo "proton_denoise: skipping ${name}.xcframework — missing ${path}" >&2
    return 0
  fi
  xcodebuild -create-xcframework \
    "${kind}" "${path}" \
    -output "${OUT_DIR}/${name}.xcframework" >/dev/null
  echo "proton_denoise: created ${name}.xcframework"
}

stage_xcframework RNNoise -library "${RNNOISE_LIB}"
stage_xcframework DTLN -library "${DTLN_LIB}"
stage_xcframework DeepFilter -framework "${DEEPFILTER_FW}"

# Absolute link: Xcode resolves symlinked build inputs lexically, and Flutter stages this
# package behind macos/Flutter/ephemeral/Packages/.packages, so a relative one would escape.
mkdir -p "${RESOURCE_DIR}"
rm -f "${RESOURCE_DIR}/DeepFilterNet3_onnx.tar.gz"
if [ -f "${DEEPFILTER_MODEL}" ]; then
  ln -sfh "${DEEPFILTER_MODEL}" "${RESOURCE_DIR}/DeepFilterNet3_onnx.tar.gz"
  echo "proton_denoise: linked DeepFilterNet3_onnx.tar.gz"
fi
