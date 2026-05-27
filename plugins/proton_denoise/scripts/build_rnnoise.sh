#!/bin/sh
# Build librnnoise.a / rnnoise.lib from upstream sources (xiph/rnnoise v0.2).
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
. "${SCRIPT_DIR}/rnnoise_cmake_env.sh"

PLUGIN_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd -P)
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

CMAKE_ARGS="-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}"

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
      CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_SYSTEM_NAME=Darwin"
      CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_OSX_SYSROOT=macosx"
    else
      DEPLOY="${IPHONEOS_DEPLOYMENT_TARGET:-15.0}"
      CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_SYSTEM_NAME=iOS"
      if [ "${PLATFORM_NAME}" = "iphonesimulator" ]; then
        CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_OSX_SYSROOT=iphonesimulator"
      else
        CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_OSX_SYSROOT=iphoneos"
      fi
    fi
    CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_OSX_ARCHITECTURES=${ARCHS}"
    CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_OSX_DEPLOYMENT_TARGET=${DEPLOY}"
    CMAKE_ARGS="${CMAKE_ARGS} -DRNNOISE_OSX_DEPLOYMENT_TARGET=${DEPLOY}"
    ;;
  host)
    BUILD_ROOT="${PLUGIN_ROOT}/.rnnoise-build/host-${CMAKE_BUILD_TYPE}"
    mkdir -p "${BUILD_ROOT}"
    CMAKE_ARGS="${CMAKE_ARGS} -DRNNOISE_OSX_DEPLOYMENT_TARGET="
    ;;
  *)
    usage
    ;;
esac

echo "RNNoise: configuring ${PLATFORM_NAME:-host} (${ARCHS:-}) in ${BUILD_ROOT}"
# Avoid reusing a CMake cache from another SDK (e.g. macOS objects linked into iOS).
rm -f "${BUILD_ROOT}/CMakeCache.txt"
_cmake_args=${CMAKE_ARGS}
set -- ${_cmake_args}
"${CMAKE_BIN}" -S "${CMAKE_DIR}" -B "${BUILD_ROOT}" "$@"

echo "RNNoise: building static library (${CMAKE_BIN})"
"${CMAKE_BIN}" --build "${BUILD_ROOT}" --target rnnoise

BUILT_LIB="${BUILD_ROOT}/librnnoise.a"
if [ ! -f "${BUILT_LIB}" ]; then
  echo "Expected ${BUILT_LIB} after build" >&2
  exit 1
fi

cp -f "${BUILT_LIB}" "${OUT_LIB}"
echo "RNNoise: installed ${OUT_LIB}"
