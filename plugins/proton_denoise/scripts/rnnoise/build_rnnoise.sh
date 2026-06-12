#!/bin/sh
# Static librnnoise.a from xiph/rnnoise v0.2 (FetchContent via cmake/rnnoise_project).
# Usage: build_rnnoise.sh <apple|host> [output.a]
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
. "${SCRIPT_DIR}/rnnoise_cmake_env.sh"

PLUGIN_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd -P)
CMAKE_DIR="${PLUGIN_ROOT}/cmake/rnnoise_project"

CMAKE_BIN=$(rnnoise_resolve_cmake) || exit 1

usage() {
  echo "Usage: $0 <apple|host> [output_library_path]" >&2
  exit 1
}

MODE=${1:-}
[ -n "${MODE}" ] || usage

if [ -n "${2:-}" ]; then
  OUT_PARENT=$(dirname "$2")
  mkdir -p "${OUT_PARENT}"
  OUT_LIB=$(cd "${OUT_PARENT}" && pwd -P)/$(basename "$2")
else
  OUT_LIB="${TARGET_TEMP_DIR:-/tmp}/rnnoise/librnnoise.a"
  mkdir -p "$(dirname "${OUT_LIB}")"
fi

CONFIGURATION=${CONFIGURATION:-Debug}
case "${CONFIGURATION}" in
  Release|Profile) CMAKE_BUILD_TYPE=Release ;;
  *) CMAKE_BUILD_TYPE=Debug ;;
esac

# CMAKE_OSX_ARCHITECTURES wants semicolon-separated ARCHS (not shell word-split).
ARCHS_CMAKE=$(echo "${ARCHS:-}" | tr ' ' ';')

case "${MODE}" in
  apple)
    if [ -z "${PLATFORM_NAME:-}" ]; then
      echo "PLATFORM_NAME is required for apple builds (macosx | iphoneos | iphonesimulator)" >&2
      exit 1
    fi
    if [ -z "${ARCHS:-}" ]; then
      echo "ARCHS is required for apple builds" >&2
      exit 1
    fi
    ARCHS_TAG=$(echo "${ARCHS}" | tr ' ' '-')
    if [ -n "${TARGET_TEMP_DIR:-}" ]; then
      BUILD_ROOT="${TARGET_TEMP_DIR}/rnnoise-cmake/${PLATFORM_NAME}-${ARCHS_TAG}-${CMAKE_BUILD_TYPE}"
    else
      BUILD_ROOT="${PLUGIN_ROOT}/.rnnoise-build/${PLATFORM_NAME}-${ARCHS_TAG}-${CMAKE_BUILD_TYPE}"
    fi
    mkdir -p "${BUILD_ROOT}"

    if [ "${PLATFORM_NAME}" = "macosx" ]; then
      DEPLOY="${MACOSX_DEPLOYMENT_TARGET:-12.0}"
      OSX_SYSROOT=macosx
      SYSTEM_NAME=Darwin
    else
      DEPLOY="${IPHONEOS_DEPLOYMENT_TARGET:-15.0}"
      SYSTEM_NAME=iOS
      if [ "${PLATFORM_NAME}" = "iphonesimulator" ]; then
        OSX_SYSROOT=iphonesimulator
      else
        OSX_SYSROOT=iphoneos
      fi
    fi
    ;;
  host)
    BUILD_ROOT="${PLUGIN_ROOT}/.rnnoise-build/host-${CMAKE_BUILD_TYPE}"
    mkdir -p "${BUILD_ROOT}"
    ;;
  *)
    usage
    ;;
esac

echo "RNNoise: configuring ${PLATFORM_NAME:-host} (${ARCHS:-}) in ${BUILD_ROOT}"
# Force reconfigure — BUILD_ROOT is per SDK/arch but stale caches have bitten us before.
rm -f "${BUILD_ROOT}/CMakeCache.txt"
if [ "${MODE}" = "apple" ]; then
  "${CMAKE_BIN}" -S "${CMAKE_DIR}" -B "${BUILD_ROOT}" \
    "-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}" \
    "-DCMAKE_SYSTEM_NAME=${SYSTEM_NAME}" \
    "-DCMAKE_OSX_SYSROOT=${OSX_SYSROOT}" \
    "-DCMAKE_OSX_ARCHITECTURES=${ARCHS_CMAKE}" \
    "-DCMAKE_OSX_DEPLOYMENT_TARGET=${DEPLOY}" \
    "-DRNNOISE_OSX_DEPLOYMENT_TARGET=${DEPLOY}"
else
  "${CMAKE_BIN}" -S "${CMAKE_DIR}" -B "${BUILD_ROOT}" \
    "-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}" \
    -DRNNOISE_OSX_DEPLOYMENT_TARGET=
fi

JOBS=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)
echo "RNNoise: building static library (${CMAKE_BIN}, -j${JOBS})"
"${CMAKE_BIN}" --build "${BUILD_ROOT}" --target rnnoise --parallel "${JOBS}"

BUILT_LIB="${BUILD_ROOT}/librnnoise.a"
if [ ! -f "${BUILT_LIB}" ]; then
  echo "Expected ${BUILT_LIB} after build" >&2
  exit 1
fi

cp -f "${BUILT_LIB}" "${OUT_LIB}"
echo "RNNoise: installed ${OUT_LIB}"
