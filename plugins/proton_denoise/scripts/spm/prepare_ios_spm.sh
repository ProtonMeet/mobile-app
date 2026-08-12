#!/bin/sh
# Stage the binary inputs of the ios/proton_denoise Swift package.
#
# SwiftPM binary targets only accept xcframeworks and, unlike CocoaPods, cannot run a
# build phase, so the device/simulator slices have to be merged up front.
#
# Usage: sh plugins/proton_denoise/scripts/spm/prepare_ios_spm.sh
set -eu

export PATH="/opt/homebrew/bin:/usr/local/bin:/Applications/CMake.app/Contents/bin:${PATH}"

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
PLUGIN_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd -P)
PACKAGE_DIR="${PLUGIN_ROOT}/ios/proton_denoise"
OUT_DIR="${PACKAGE_DIR}/VendoredFrameworks"
RESOURCE_DIR="${PACKAGE_DIR}/Sources/proton_denoise/Resources"
RNNOISE_LIB="${PLUGIN_ROOT}/third_party/rnnoise/lib/ios"
DTLN_LIB="${PLUGIN_ROOT}/third_party/dtln-rs/lib/ios"
DEEPFILTER_MODEL="${PLUGIN_ROOT}/third_party/deepfilter/models/DeepFilterNet3_onnx.tar.gz"
DEEPFILTER_XC="${PLUGIN_ROOT}/third_party/deepfilter/ios/DeepFilter.xcframework"

CONFIGURATION="${CONFIGURATION:-Release}"
export CONFIGURATION

mkdir -p "${OUT_DIR}"

# RNNoise is built from source and gitignored (CocoaPods did this in a script phase).
if [ ! -f "${RNNOISE_LIB}/device/librnnoise.a" ] || [ ! -f "${RNNOISE_LIB}/simulator/librnnoise.a" ]; then
  PLATFORM_NAME=iphoneos ARCHS="arm64" \
    sh "${PLUGIN_ROOT}/scripts/rnnoise/build_rnnoise.sh" apple "${RNNOISE_LIB}/device/librnnoise.a"
  PLATFORM_NAME=iphonesimulator ARCHS="arm64 x86_64" \
    sh "${PLUGIN_ROOT}/scripts/rnnoise/build_rnnoise.sh" apple "${RNNOISE_LIB}/simulator/librnnoise.a"
fi

make_xcframework() {
  name="$1"
  device="$2"
  simulator="$3"
  if [ ! -f "${device}" ] || [ ! -f "${simulator}" ]; then
    echo "proton_denoise: skipping ${name}.xcframework — missing ${device} or ${simulator}" >&2
    return 0
  fi
  rm -rf "${OUT_DIR}/${name}.xcframework"
  xcodebuild -create-xcframework \
    -library "${device}" \
    -library "${simulator}" \
    -output "${OUT_DIR}/${name}.xcframework" >/dev/null
  echo "proton_denoise: created ${name}.xcframework"
}

make_xcframework RNNoise "${RNNOISE_LIB}/device/librnnoise.a" "${RNNOISE_LIB}/simulator/librnnoise.a"

# dtln-rs bundles its own TensorFlow Lite, and proton_video_effects force-loads MediaPipe's
# (a different build) into the same binary. Left visible, the two copies get mixed by the linker
# and dtln crashes inside dtln_create. Prelinking each slice into one object that exports only
# the _dtln_* entry points keeps dtln on its own TFLite.
prelink_dtln_slice() {
  slice="$1"
  platform="$2"
  out="$3"
  lib="${DTLN_LIB}/${slice}/libdtln.a"
  tflite="${DTLN_LIB}/${slice}/libdtln_tflite.a"
  [ -f "${lib}" ] && [ -f "${tflite}" ] || return 1

  exports="${STAGE}/dtln_exports.txt"
  printf '_dtln_*\n' >"${exports}"
  arch=$(lipo -archs "${lib}" | tr ' ' '\n' | head -1)
  mkdir -p "$(dirname "${out}")"
  ld -r -arch "${arch}" -platform_version "${platform}" "${IPHONEOS_DEPLOYMENT_TARGET:-15.0}" "${IPHONEOS_DEPLOYMENT_TARGET:-15.0}" \
    -all_load "${lib}" "${tflite}" \
    -exported_symbols_list "${exports}" \
    -o "${STAGE}/${slice}/dtln_merged.o"
  libtool -static -o "${out}" "${STAGE}/${slice}/dtln_merged.o"
}

STAGE=$(mktemp -d)
mkdir -p "${STAGE}/device" "${STAGE}/simulator"
if prelink_dtln_slice device ios "${STAGE}/device/libdtln.a" &&
  prelink_dtln_slice simulator ios-simulator "${STAGE}/simulator/libdtln.a"; then
  make_xcframework DTLN "${STAGE}/device/libdtln.a" "${STAGE}/simulator/libdtln.a"
else
  echo "proton_denoise: skipping DTLN.xcframework — missing dtln archives" >&2
fi
rm -rf "${STAGE}"

# Absolute links: Xcode resolves symlinked build inputs lexically, and Flutter stages this
# package behind ios/Flutter/ephemeral/Packages/.packages, so relative ones would escape.
rm -f "${OUT_DIR}/DeepFilter.xcframework"
if [ -d "${DEEPFILTER_XC}" ]; then
  ln -sfh "${DEEPFILTER_XC}" "${OUT_DIR}/DeepFilter.xcframework"
  echo "proton_denoise: linked DeepFilter.xcframework"
fi

mkdir -p "${RESOURCE_DIR}"
rm -f "${RESOURCE_DIR}/DeepFilterNet3_onnx.tar.gz"
if [ -f "${DEEPFILTER_MODEL}" ]; then
  ln -sfh "${DEEPFILTER_MODEL}" "${RESOURCE_DIR}/DeepFilterNet3_onnx.tar.gz"
  echo "proton_denoise: linked DeepFilterNet3_onnx.tar.gz"
fi
