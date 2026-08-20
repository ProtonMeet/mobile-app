#!/bin/sh
# Stage the binary inputs of the ios/proton_video_effects Swift package.
#
# The podspec got MediaPipe from CocoaPods trunk; SwiftPM cannot depend on a pod, so the same
# release is vendored here. MediaPipeTasksCommon ships its calculator graphs as a plain .a that
# the pod force-loads per SDK — SwiftPM has no per-SDK linker settings, so the device and
# simulator archives are merged into one xcframework under a single library name and force-loaded
# from ${BUILT_PRODUCTS_DIR} (see Package.swift).
#
# MediaPipe is not stored in plugins/plugin-cache — reuse CocoaPods cache or download the pod
# release tarball when staging (same source as `pod install`).
#
# Usage: sh plugins/proton_video_effects/scripts/spm/prepare_ios_spm.sh
set -eu

MEDIAPIPE_VERSION="${MEDIAPIPE_VERSION:-0.10.35}"
GRAPH_LIBRARY_NAME="libMediaPipeTasksCommonGraph.a"

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
PLUGIN_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd -P)
PACKAGE_DIR="${PLUGIN_ROOT}/ios/proton_video_effects"
OUT_DIR="${PACKAGE_DIR}/VendoredFrameworks"
RESOURCE_DIR="${PACKAGE_DIR}/Sources/proton_video_effects/Resources"
VENDOR_DIR="${PLUGIN_ROOT}/third_party/mediapipe/ios"
POD_CACHE="${HOME}/Library/Caches/CocoaPods/Pods/Release"

mkdir -p "${OUT_DIR}" "${RESOURCE_DIR}" "${VENDOR_DIR}"

copy_pod_frameworks() {
  src="$1"
  dest="$2"
  mkdir -p "${dest}"
  cp -Rc "${src}/." "${dest}/" 2>/dev/null || cp -R "${src}/." "${dest}/"
}

# CocoaPods cache → remote pod tarball (not committed in plugin-cache).
fetch_pod() {
  pod_name="$1"
  dest="${VENDOR_DIR}/${pod_name}"
  if [ -d "${dest}/${pod_name}.xcframework" ]; then
    return 0
  fi

  cached=$(find "${POD_CACHE}/${pod_name}" -maxdepth 1 -type d -name "${MEDIAPIPE_VERSION}-*" 2>/dev/null | head -1)
  if [ -n "${cached}" ]; then
    echo "proton_video_effects: using CocoaPods cache for ${pod_name}"
    copy_pod_frameworks "${cached}/frameworks" "${dest}"
    return 0
  fi

  url=$(pod spec cat --version="${MEDIAPIPE_VERSION}" "${pod_name}" 2>/dev/null |
    sed -n 's/.*"http": "\(.*\)".*/\1/p' | head -1)
  if [ -z "${url}" ]; then
    echo "proton_video_effects: cannot resolve a download URL for ${pod_name} ${MEDIAPIPE_VERSION}" >&2
    echo "  Run: cd ios && pod install   (or ensure network access for pod download)" >&2
    exit 1
  fi
  echo "proton_video_effects: downloading ${pod_name} ${MEDIAPIPE_VERSION}"
  tmp=$(mktemp -d)
  curl -fsSL "${url}" -o "${tmp}/pod.tar.gz"
  tar -xzf "${tmp}/pod.tar.gz" -C "${tmp}"
  copy_pod_frameworks "${tmp}/frameworks" "${dest}"
  rm -rf "${tmp}"
}

fetch_pod MediaPipeTasksCommon
fetch_pod MediaPipeTasksVision

link_xcframework() {
  name="$1"
  source_path="$2"
  rm -rf "${OUT_DIR}/${name}.xcframework"
  # Absolute: Xcode resolves symlinked build inputs lexically, and Flutter stages this package
  # behind ios/Flutter/ephemeral/Packages/.packages, so a relative link would escape.
  ln -sfh "${source_path}" "${OUT_DIR}/${name}.xcframework"
  echo "proton_video_effects: linked ${name}.xcframework"
}

link_xcframework MediaPipeTasksCommon \
  "${VENDOR_DIR}/MediaPipeTasksCommon/MediaPipeTasksCommon.xcframework"
link_xcframework MediaPipeTasksVision \
  "${VENDOR_DIR}/MediaPipeTasksVision/MediaPipeTasksVision.xcframework"

# Both slices must share a library name so Package.swift can force-load one predictable path.
GRAPH_DIR="${VENDOR_DIR}/MediaPipeTasksCommon/graph_libraries"
STAGE=$(mktemp -d)
for slice in device simulator; do
  mkdir -p "${STAGE}/${slice}"
  ln -f "${GRAPH_DIR}/libMediaPipeTasksCommon_${slice}_graph.a" "${STAGE}/${slice}/${GRAPH_LIBRARY_NAME}" 2>/dev/null ||
    cp "${GRAPH_DIR}/libMediaPipeTasksCommon_${slice}_graph.a" "${STAGE}/${slice}/${GRAPH_LIBRARY_NAME}"
done
rm -rf "${OUT_DIR}/MediaPipeTasksCommonGraph.xcframework"
xcodebuild -create-xcframework \
  -library "${STAGE}/device/${GRAPH_LIBRARY_NAME}" \
  -library "${STAGE}/simulator/${GRAPH_LIBRARY_NAME}" \
  -output "${OUT_DIR}/MediaPipeTasksCommonGraph.xcframework" >/dev/null
rm -rf "${STAGE}"
echo "proton_video_effects: created MediaPipeTasksCommonGraph.xcframework"

for model in "${PLUGIN_ROOT}/ios/Resources"/*.tflite; do
  [ -e "${model}" ] || continue
  target="${RESOURCE_DIR}/$(basename "${model}")"
  rm -f "${target}"
  ln -sfh "${model}" "${target}"
done
echo "proton_video_effects: linked tflite models"
