#!/bin/sh
# Xcode build phase: compile RNNoise for the active SDK/arch slice(s).
set -eu

BASEDIR=$(cd "$(dirname "$0")" && pwd -P)
. "${BASEDIR}/rnnoise_cmake_env.sh"

OUT_LIB="${BUILT_PRODUCTS_DIR}/librnnoise.a"
mkdir -p "${BUILT_PRODUCTS_DIR}"

# CocoaPods script phases do not always export TARGET_TEMP_DIR; DERIVED_FILE_DIR is per target/SDK.
if [ -z "${TARGET_TEMP_DIR:-}" ] && [ -n "${DERIVED_FILE_DIR:-}" ]; then
  export TARGET_TEMP_DIR="${DERIVED_FILE_DIR}"
fi

export PLATFORM_NAME EFFECTIVE_PLATFORM_NAME ARCHS CONFIGURATION
sh "${BASEDIR}/build_rnnoise.sh" apple "${OUT_LIB}"

touch "${OUT_LIB}"
