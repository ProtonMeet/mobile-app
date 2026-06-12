#!/usr/bin/env bash
# Shared paths and helpers for DeepFilterNet (libDF) native builds.
set -euo pipefail

deepfilter_repo_root() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)"
  cd "${script_dir}/../../../.." && pwd
}

DEEPFILTER_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)"
# shellcheck source=../native_build_env.sh
source "${DEEPFILTER_SCRIPT_DIR}/../native_build_env.sh"
DEEPFILTER_ROOT="$(deepfilter_repo_root)"
DEEPFILTER_PLUGIN="${DEEPFILTER_ROOT}/plugins/proton_denoise"
DEEPFILTER_THIRD_PARTY="${DEEPFILTER_PLUGIN}/third_party/deepfilter"
DEEPFILTER_LIB_OUT="${DEEPFILTER_THIRD_PARTY}/lib"
DEEPFILTER_MODELS_OUT="${DEEPFILTER_THIRD_PARTY}/models"
DEEPFILTER_INCLUDE_OUT="${DEEPFILTER_THIRD_PARTY}/include/deep_filter.h"
DEEPFILTER_XCFRAMEWORK_OUT="${DEEPFILTER_THIRD_PARTY}/ios/DeepFilter.xcframework"
DEEPFILTER_MACOS_FRAMEWORK_OUT="${DEEPFILTER_THIRD_PARTY}/macos/DeepFilter.framework"
DEEPFILTER_STAGING_DIR="${DEEPFILTER_STAGING_DIR:-${DEEPFILTER_ROOT}/.local/deepfilter-staging}"
DEEPFILTER_APPLE_STAGING="${DEEPFILTER_STAGING_DIR}/apple"
DEEPFILTER_MODEL3="${DEEPFILTER_MODELS_OUT}/DeepFilterNet3_onnx.tar.gz"
DEEPFILTER_MACOS_ARCHS="${DEEPFILTER_MACOS_ARCHS:-arm64 x86_64}"

DEEPFILTER_SRC="${DEEPFILTER_SRC:-${DEEPFILTER_ROOT}/.local/deepfilter-src}"
DEEPFILTER_GIT_URL="${DEEPFILTER_GIT_URL:-https://github.com/Rikorose/DeepFilterNet.git}"
DEEPFILTER_GIT_REF="${DEEPFILTER_GIT_REF:-main}"
DEEPFILTER_CARGO_PROFILE="${DEEPFILTER_CARGO_PROFILE:-release}"
DEEPFILTER_RUSTFLAGS="${DEEPFILTER_RUSTFLAGS:--C link-arg=-fobjc-link-runtime}"

deepfilter_prepend_path() {
  native_prepend_path
}

deepfilter_require_cmd() {
  native_require_cmd "$@"
}

deepfilter_resolve_rust() {
  native_resolve_rust
}

deepfilter_ensure_sources() {
  if [[ -d "${DEEPFILTER_SRC}/.git" ]]; then
    git -C "${DEEPFILTER_SRC}" fetch --depth 1 origin "${DEEPFILTER_GIT_REF}" 2>/dev/null || true
    git -C "${DEEPFILTER_SRC}" checkout "${DEEPFILTER_GIT_REF}" 2>/dev/null || true
    return 0
  fi
  mkdir -p "$(dirname "${DEEPFILTER_SRC}")"
  git clone --depth 1 --branch "${DEEPFILTER_GIT_REF}" "${DEEPFILTER_GIT_URL}" "${DEEPFILTER_SRC}"
}

deepfilter_install_rust_target() {
  local triple="$1"
  if ! rustup target list --installed | grep -qx "${triple}"; then
    rustup target add "${triple}"
  fi
}

deepfilter_apple_slice_config() {
  local platform="$1"
  local arch="$2"
  case "${platform}:${arch}" in
    iphoneos:arm64)
      DEEPFILTER_SLICE_TRIPLE="aarch64-apple-ios"
      DEEPFILTER_SLICE_SDK="iphoneos"
      ;;
    iphonesimulator:arm64)
      DEEPFILTER_SLICE_TRIPLE="aarch64-apple-ios-sim"
      DEEPFILTER_SLICE_SDK="iphonesimulator"
      ;;
    iphonesimulator:x86_64)
      DEEPFILTER_SLICE_TRIPLE="x86_64-apple-ios"
      DEEPFILTER_SLICE_SDK="iphonesimulator"
      ;;
    macosx:arm64)
      DEEPFILTER_SLICE_TRIPLE="aarch64-apple-darwin"
      DEEPFILTER_SLICE_SDK="macosx"
      ;;
    macosx:x86_64)
      DEEPFILTER_SLICE_TRIPLE="x86_64-apple-darwin"
      DEEPFILTER_SLICE_SDK="macosx"
      ;;
    *)
      echo "deepfilter: unsupported Apple platform ${platform}/${arch}" >&2
      return 1
      ;;
  esac
  export DEEPFILTER_SLICE_TRIPLE DEEPFILTER_SLICE_SDK
}

deepfilter_triple_to_cargo_env() {
  native_triple_to_cargo_env "$@"
}

deepfilter_export_apple_cc_env() {
  native_export_apple_cc_env "$1"
}

deepfilter_cargo_static_lib() {
  local triple="$1"
  echo "${DEEPFILTER_SRC}/target/${triple}/release/libdf.a"
}

deepfilter_copy_built_lib() {
  local triple="$1"
  local dest="$2"
  local rust_lib
  rust_lib="$(deepfilter_cargo_static_lib "${triple}")"
  if [[ -f "${rust_lib}" ]]; then
    deepfilter_install_lib "${dest}" "${rust_lib}"
    return 0
  fi
  echo "deepfilter: missing ${rust_lib}" >&2
  return 1
}

deepfilter_stage_model() {
  mkdir -p "${DEEPFILTER_MODELS_OUT}"
  local model_src="${DEEPFILTER_SRC}/models/DeepFilterNet3_onnx.tar.gz"
  if [[ ! -f "${model_src}" ]]; then
    echo "deepfilter: model not found at ${model_src}" >&2
    return 1
  fi
  cp -f "${model_src}" "${DEEPFILTER_MODELS_OUT}/DeepFilterNet3_onnx.tar.gz"
}

deepfilter_write_capi_header() {
  mkdir -p "$(dirname "${DEEPFILTER_INCLUDE_OUT}")"
  cat >"${DEEPFILTER_INCLUDE_OUT}" <<'EOF'
#ifndef DEEP_FILTER_H_
#define DEEP_FILTER_H_

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct DFState DFState;

DFState* df_create(const char* path, float atten_lim, const char* log_level);
size_t df_get_frame_length(DFState* st);
float df_process_frame(DFState* st, float* input, float* output);
void df_set_atten_lim(DFState* st, float lim_db);
void df_free(DFState* st);

#ifdef __cplusplus
}
#endif

#endif  // DEEP_FILTER_H_
EOF
}

deepfilter_install_lib() {
  local dest="$1"
  local src="$2"
  mkdir -p "$(dirname "${dest}")"
  cp -f "${src}" "${dest}"
  echo "deepfilter: installed ${dest}"
}

# Rust cdylib records an absolute path under target/.../deps/; apps must embed via @rpath.
DEEPFILTER_MACOS_FRAMEWORK_INSTALL_NAME="@rpath/DeepFilter.framework/Versions/A/DeepFilter"
DEEPFILTER_IOS_FRAMEWORK_INSTALL_NAME="@rpath/DeepFilter.framework/DeepFilter"

deepfilter_fixup_dylib_install_name() {
  local dylib="$1"
  local install_name="$2"
  if [[ ! -f "${dylib}" ]]; then
    echo "deepfilter: missing dylib ${dylib}" >&2
    return 1
  fi
  deepfilter_require_cmd install_name_tool
  local old_id
  old_id="$(otool -D "${dylib}" 2>/dev/null | awk 'NF && $1 !~ /:/ {print; exit}')"
  if [[ -z "${old_id}" ]]; then
    old_id="$(otool -D "${dylib}" 2>/dev/null | tail -1)"
  fi
  if [[ "${old_id}" == "${install_name}" ]]; then
    return 0
  fi
  install_name_tool -id "${install_name}" "${dylib}"
  if [[ -n "${old_id}" && "${old_id}" != "${install_name}" ]]; then
    install_name_tool -change "${old_id}" "${install_name}" "${dylib}" 2>/dev/null || true
  fi
  echo "deepfilter: install name ${install_name} -> ${dylib}"
}

deepfilter_macos_fat_out() {
  echo "${DEEPFILTER_APPLE_STAGING}/macos/libdeepfilter.dylib"
}

deepfilter_macos_slice_out() {
  local arch="$1"
  echo "${DEEPFILTER_APPLE_STAGING}/macos/${arch}/libdeepfilter.dylib"
}

deepfilter_ios_slice_out() {
  local platform="$1"
  local arch="$2"
  case "${platform}" in
    iphoneos)
      echo "${DEEPFILTER_APPLE_STAGING}/ios/device-${arch}/libdeepfilter.dylib"
      ;;
    iphonesimulator)
      echo "${DEEPFILTER_APPLE_STAGING}/ios/simulator-${arch}/libdeepfilter.dylib"
      ;;
    *)
      echo "deepfilter: unsupported iOS platform ${platform}" >&2
      return 1
      ;;
  esac
}

# Create a fat/universal dylib from per-arch slices (macOS).
deepfilter_lipo_fat() {
  local out_fat="$1"
  shift
  deepfilter_require_cmd lipo
  mkdir -p "$(dirname "${out_fat}")"
  if [[ "$#" -eq 1 ]]; then
    cp -f "$1" "${out_fat}"
    echo "deepfilter: installed single-arch ${out_fat}"
    return 0
  fi
  lipo -create "$@" -output "${out_fat}"
  lipo -info "${out_fat}"
  echo "deepfilter: installed fat ${out_fat}"
}

deepfilter_finalize_macos_install() {
  local fat_out
  fat_out="$(deepfilter_macos_fat_out)"
  if [[ ! -f "${fat_out}" ]]; then
    echo "deepfilter: missing ${fat_out}" >&2
    return 1
  fi
  deepfilter_fixup_dylib_install_name "${fat_out}" "${DEEPFILTER_MACOS_FRAMEWORK_INSTALL_NAME}"
}

deepfilter_android_abi_out() {
  local abi="$1"
  case "${abi}" in
    armeabi-v7a)
      echo "${DEEPFILTER_LIB_OUT}/android/armeabi-v7a/libdeepfilter.so"
      ;;
    arm64-v8a)
      echo "${DEEPFILTER_LIB_OUT}/android/arm64-v8a/libdeepfilter.so"
      ;;
    x86_64)
      echo "${DEEPFILTER_LIB_OUT}/android/x86_64/libdeepfilter.so"
      ;;
    *)
      echo "deepfilter: unknown Android ABI ${abi}" >&2
      return 1
      ;;
  esac
}

deepfilter_cargo_target_env_key() {
  native_triple_to_cargo_env "$@"
}

deepfilter_build_android_abi() {
  local abi="$1"
  local out_lib="$2"
  local cargo_target="${CARGO_BUILD_TARGET:?CARGO_BUILD_TARGET not set}"
  local cargo_env_key linker_var ar_var

  deepfilter_install_rust_target "${cargo_target}"

  cargo_env_key="$(deepfilter_cargo_target_env_key "${cargo_target}")"
  linker_var="CARGO_TARGET_${cargo_env_key}_LINKER"
  ar_var="CARGO_TARGET_${cargo_env_key}_AR"
  if [[ -n "${CC:-}" ]]; then
    export "${linker_var}=${CC}"
  fi
  if [[ -n "${AR:-}" ]]; then
    export "${ar_var}=${AR}"
  fi

  echo "deepfilter: building libdf for ${cargo_target} (${abi})..."
  local cargo_out="${DEEPFILTER_SRC}/target"
  mkdir -p "${cargo_out}"
  (
    cd "${DEEPFILTER_SRC}"
    unset RUSTFLAGS DEEPFILTER_RUSTFLAGS
    export CARGO_TARGET_DIR="${cargo_out}"
    cargo rustc \
      --release \
      --target "${cargo_target}" \
      -p deep_filter \
      --features "capi,tract,default-model" \
      --crate-type cdylib
  )

  local so="${DEEPFILTER_SRC}/target/${cargo_target}/release/libdf.so"
  if [[ ! -f "${so}" ]]; then
    echo "deepfilter: missing ${so}" >&2
    return 1
  fi
  deepfilter_install_lib "${out_lib}" "${so}"
  deepfilter_stage_model
  deepfilter_write_capi_header
}

deepfilter_build_apple_slice() {
  local platform="$1"
  local arch="$2"
  local out_lib="$3"

  deepfilter_apple_slice_config "${platform}" "${arch}"
  deepfilter_install_rust_target "${DEEPFILTER_SLICE_TRIPLE}"
  deepfilter_export_apple_cc_env "${DEEPFILTER_SLICE_TRIPLE}"

  echo "deepfilter: building libdf for ${DEEPFILTER_SLICE_TRIPLE}..."
  local cargo_target="${DEEPFILTER_SRC}/target"
  local cargo_env_key cc_var cxx_var cflags_var cxxflags_var
  cargo_env_key="$(deepfilter_triple_to_cargo_env "${DEEPFILTER_SLICE_TRIPLE}")"
  cc_var="CC_${cargo_env_key}"
  cxx_var="CXX_${cargo_env_key}"
  cflags_var="CFLAGS_${cargo_env_key}"
  cxxflags_var="CXXFLAGS_${cargo_env_key}"
  mkdir -p "${cargo_target}"
  (
    cd "${DEEPFILTER_SRC}"
    unset RUSTFLAGS
    export CARGO_TARGET_DIR="${cargo_target}"
    # cc-rs / tract-linalg sometimes ignore CC_<triple>; mirror into CC/CFLAGS for cross builds.
    if [[ -n "${!cc_var:-}" ]]; then
      export CC="${!cc_var}"
      export CXX="${!cxx_var:-${!cc_var}++}"
      export CFLAGS="${!cflags_var:-}"
      export CXXFLAGS="${!cxxflags_var:-${!cflags_var:-}}"
    fi
    cargo rustc \
      --release \
      --target "${DEEPFILTER_SLICE_TRIPLE}" \
      -p deep_filter \
      --features "capi,tract,default-model" \
      --crate-type cdylib
  )

  local dylib="${DEEPFILTER_SRC}/target/${DEEPFILTER_SLICE_TRIPLE}/release/libdf.dylib"
  if [[ ! -f "${dylib}" ]]; then
    echo "deepfilter: missing ${dylib}" >&2
    return 1
  fi
  deepfilter_install_lib "${out_lib}" "${dylib}"
  case "${platform}" in
    macosx)
      deepfilter_fixup_dylib_install_name "${out_lib}" "${DEEPFILTER_MACOS_FRAMEWORK_INSTALL_NAME}"
      ;;
    iphoneos | iphonesimulator)
      deepfilter_fixup_dylib_install_name "${out_lib}" "${DEEPFILTER_IOS_FRAMEWORK_INSTALL_NAME}"
      ;;
  esac
  deepfilter_stage_model
  deepfilter_write_capi_header
  if [[ "${platform}" == iphoneos || "${platform}" == iphonesimulator ]]; then
    sh "${DEEPFILTER_SCRIPT_DIR}/package_deepfilter_framework.sh"
  fi
}
