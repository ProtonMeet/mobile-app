#!/bin/sh
# Symlink shared darwin/cpp sources into ios/ or macos/ Classes/ + Cpp/ for CocoaPods.
# CocoaPods must compile Swift from paths under the pod root to emit the module map.
set -e

PLATFORM_DIR="${1:-${PWD}}"
PLUGIN_ROOT="$(cd "${PLATFORM_DIR}/.." && pwd)"
DARWIN_CLASSES="${PLUGIN_ROOT}/common/darwin/Classes"
CPP_SRC="${PLUGIN_ROOT}/common/cpp/src"

mkdir -p "${PLATFORM_DIR}/Classes" "${PLATFORM_DIR}/Cpp"
rm -f "${PLATFORM_DIR}/Classes"/*.swift "${PLATFORM_DIR}/Cpp"/*.cc 2>/dev/null || true

for f in "${DARWIN_CLASSES}/"*.swift; do
  [ -e "$f" ] || continue
  ln -sfh "$f" "${PLATFORM_DIR}/Classes/$(basename "$f")"
done

ln -sfh "${CPP_SRC}/proton_rnnoise_c_api.cc" "${PLATFORM_DIR}/Cpp/"
ln -sfh "${CPP_SRC}/proton_rnnoise_processor.cc" "${PLATFORM_DIR}/Cpp/"
if [ -f "${CPP_SRC}/proton_dtln_c_api.cc" ]; then
  ln -sfh "${CPP_SRC}/proton_dtln_c_api.cc" "${PLATFORM_DIR}/Cpp/"
fi
if [ -f "${CPP_SRC}/proton_deepfilter_processor.cc" ]; then
  ln -sfh "${CPP_SRC}/proton_deepfilter_processor.cc" "${PLATFORM_DIR}/Cpp/"
fi

PLATFORM_NAME="$(basename "${PLATFORM_DIR}")"
DEEPFILTER_IOS_XC="${PLUGIN_ROOT}/third_party/deepfilter/ios/DeepFilter.xcframework"
DEEPFILTER_MAC_FW="${PLUGIN_ROOT}/third_party/deepfilter/macos/DeepFilter.framework"
DEEPFILTER_MODEL="${PLUGIN_ROOT}/third_party/deepfilter/models/DeepFilterNet3_onnx.tar.gz"
mkdir -p "${PLATFORM_DIR}/Vendored" "${PLATFORM_DIR}/Resources"
rm -f "${PLATFORM_DIR}/Resources/DeepFilterNet3_onnx.tar.gz"
if [ -f "${DEEPFILTER_MODEL}" ]; then
  ln -sfh "${DEEPFILTER_MODEL}" "${PLATFORM_DIR}/Resources/DeepFilterNet3_onnx.tar.gz"
fi
# Never mix Apple platforms: a macOS .framework in ios/Vendored breaks device linking.
# TODO: later we can merge all to single xcframework
rm -f "${PLATFORM_DIR}/Vendored/DeepFilter.framework" "${PLATFORM_DIR}/Vendored/DeepFilter.xcframework"
case "${PLATFORM_NAME}" in
  ios)
    if [ -d "${DEEPFILTER_IOS_XC}" ]; then
      ln -sfh "${DEEPFILTER_IOS_XC}" "${PLATFORM_DIR}/Vendored/DeepFilter.xcframework"
    fi
    ;;
  macos)
    if [ -d "${DEEPFILTER_MAC_FW}" ]; then
      ln -sfh "${DEEPFILTER_MAC_FW}" "${PLATFORM_DIR}/Vendored/DeepFilter.framework"
    fi
    ;;
esac
