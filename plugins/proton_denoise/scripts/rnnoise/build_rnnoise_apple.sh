#!/bin/sh
# CocoaPods / Xcode script phase → librnnoise.a in BUILT_PRODUCTS_DIR.
set -eu

BASEDIR=$(cd "$(dirname "$0")" && pwd -P)
. "${BASEDIR}/rnnoise_cmake_env.sh"

OUT_LIB="${BUILT_PRODUCTS_DIR}/librnnoise.a"
mkdir -p "${BUILT_PRODUCTS_DIR}"

# Xcode does not always set TARGET_TEMP_DIR; DERIVED_FILE_DIR is a safe cmake cache parent.
if [ -z "${TARGET_TEMP_DIR:-}" ] && [ -n "${DERIVED_FILE_DIR:-}" ]; then
  export TARGET_TEMP_DIR="${DERIVED_FILE_DIR}"
fi

export PLATFORM_NAME ARCHS CONFIGURATION
sh "${BASEDIR}/build_rnnoise.sh" apple "${OUT_LIB}"
# Touch so CocoaPods / Xcode see the declared output artifact as fresh.
touch "${OUT_LIB}"
