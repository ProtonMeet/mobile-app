#!/usr/bin/env bash
# Shared paths and tool discovery for dtln-rs native builds (proton_denoise third_party).
# shellcheck disable=SC2034
set -euo pipefail

dtln_rs_repo_root() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)"
  cd "${script_dir}/../../../.." && pwd
}

DTLN_RS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)"
# shellcheck source=../native_build_env.sh
source "${DTLN_RS_SCRIPT_DIR}/../native_build_env.sh"
DTLN_RS_ROOT="$(dtln_rs_repo_root)"
DTLN_RS_PLUGIN="${DTLN_RS_ROOT}/plugins/proton_denoise"
DTLN_RS_THIRD_PARTY="${DTLN_RS_PLUGIN}/third_party/dtln-rs"
DTLN_RS_LIB_OUT="${DTLN_RS_THIRD_PARTY}/lib"
DTLN_RS_INCLUDE_OUT="${DTLN_RS_THIRD_PARTY}/include/dtln.h"
DTLN_RS_STAGING_DIR="${DTLN_RS_STAGING_DIR:-${DTLN_RS_ROOT}/.local/dtln-rs-staging}"

# Space-separated arch list for fat macOS / simulator libs.
DTLN_RS_MACOS_ARCHS="${DTLN_RS_MACOS_ARCHS:-arm64 x86_64}"
# Apple Silicon: arm64 simulator only (Xcode default). Override for universal sim:
#   DTLN_RS_IOS_SIM_ARCHS="arm64 x86_64" ./utilities/build-dtln-rs.sh ios
if [[ -z "${DTLN_RS_IOS_SIM_ARCHS:-}" ]]; then
  case "$(uname -m)" in
    arm64) DTLN_RS_IOS_SIM_ARCHS="arm64" ;;
    *) DTLN_RS_IOS_SIM_ARCHS="arm64 x86_64" ;;
  esac
fi

# Upstream checkout (pristine) and mutable build tree (patches applied per build).
DTLN_RS_SRC="${DTLN_RS_SRC:-${DTLN_RS_ROOT}/.local/dtln-rs-src}"
DTLN_RS_BUILD_TREE="${DTLN_RS_BUILD_TREE:-${DTLN_RS_ROOT}/.local/dtln-rs-build}"
DTLN_RS_GIT_URL="${DTLN_RS_GIT_URL:-https://github.com/DataDog/dtln-rs.git}"
DTLN_RS_GIT_REF="${DTLN_RS_GIT_REF:-master}"
DTLN_RS_CARGO_PROFILE="${DTLN_RS_CARGO_PROFILE:-release}"

# Extra flags passed to every `cargo rustc` (e.g. -C panic=abort for iOS).
DTLN_RS_RUSTFLAGS="${DTLN_RS_RUSTFLAGS:-}"

dtln_rs_prepend_path() {
  native_prepend_path
}

dtln_rs_require_cmd() {
  native_require_cmd "$@"
}

dtln_rs_resolve_rust() {
  native_resolve_rust
  if [[ -z "${RUSTUP_HOME:-}" ]] && ! command -v rustup >/dev/null 2>&1; then
    echo "dtln-rs build: rustup recommended for cross-target installs" >&2
  fi
}

dtln_rs_resolve_ndk() {
  dtln_rs_prepend_path
  if [[ -n "${ANDROID_NDK_HOME:-}" && -d "${ANDROID_NDK_HOME}" ]]; then
    return 0
  fi
  local props="${DTLN_RS_ROOT}/android/local.properties"
  if [[ -f "${props}" ]]; then
    local sdk_dir
    sdk_dir="$(grep -E '^sdk\.dir=' "${props}" | cut -d= -f2- | tr -d '\r')"
    if [[ -n "${sdk_dir}" ]]; then
      local ndk_ver ndk_root
      ndk_ver="$(
        grep 'ndkVersion' "${DTLN_RS_ROOT}/android/gradle/libs.versions.toml" 2>/dev/null \
          | head -1 \
          | sed -E 's/.*=\s*"([^"]+)".*/\1/' \
          || true
      )"
      if [[ -n "${ndk_ver}" && -d "${sdk_dir}/ndk/${ndk_ver}" ]]; then
        export ANDROID_NDK_HOME="${sdk_dir}/ndk/${ndk_ver}"
        return 0
      fi
      ndk_root="$(ls -d "${sdk_dir}"/ndk/* 2>/dev/null | sort -V | tail -n 1 || true)"
      if [[ -n "${ndk_root}" ]]; then
        export ANDROID_NDK_HOME="${ndk_root}"
        return 0
      fi
    fi
  fi
  echo "dtln-rs build: set ANDROID_NDK_HOME (Meet uses NDK from android/local.properties)" >&2
  exit 1
}

dtln_rs_android_ndk_env() {
  local abi="$1"
  dtln_rs_resolve_ndk
  dtln_rs_require_cmd python3

  local host_tag llvm_prebuilt
  case "$(uname -s)/$(uname -m)" in
    Darwin/arm64) host_tag="darwin-arm64" ;;
    Darwin/x86_64) host_tag="darwin-x86_64" ;;
    Linux/x86_64) host_tag="linux-x86_64" ;;
    Linux/aarch64) host_tag="linux-aarch64" ;;
    *)
      echo "dtln-rs build: unsupported Android host $(uname -s)/$(uname -m)" >&2
      exit 1
      ;;
  esac

  llvm_prebuilt="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/${host_tag}"
  if [[ ! -d "${llvm_prebuilt}" ]]; then
    local fallback_tag=""
    case "${host_tag}" in
      darwin-arm64) fallback_tag="darwin-x86_64" ;;
      linux-aarch64) fallback_tag="linux-x86_64" ;;
    esac
    if [[ -n "${fallback_tag}" ]]; then
      local fallback_prebuilt="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/${fallback_tag}"
      if [[ -d "${fallback_prebuilt}" ]]; then
        echo "dtln-rs: using NDK prebuilt ${fallback_tag} (no ${host_tag})" >&2
        llvm_prebuilt="${fallback_prebuilt}"
      fi
    fi
  fi
  if [[ ! -d "${llvm_prebuilt}" ]]; then
    echo "dtln-rs build: NDK llvm prebuilt missing: ${llvm_prebuilt}" >&2
    exit 1
  fi

  export DTLN_RS_ANDROID_ABI="${abi}"

  local api=24
  case "${abi}" in
    armeabi-v7a)
      export CC="${llvm_prebuilt}/bin/armv7a-linux-androideabi${api}-clang"
      export CXX="${llvm_prebuilt}/bin/armv7a-linux-androideabi${api}-clang++"
      export CARGO_BUILD_TARGET="armv7-linux-androideabi"
      export AR="${llvm_prebuilt}/bin/llvm-ar"
      export DTLN_RS_TFLITE_LIB_DIR="${DTLN_RS_TFLITE_LIB_DIR:-${DTLN_RS_BUILD_TREE}/tflite/lib/android/armeabi-v7a}"
      ;;
    arm64-v8a)
      export CC="${llvm_prebuilt}/bin/aarch64-linux-android${api}-clang"
      export CXX="${llvm_prebuilt}/bin/aarch64-linux-android${api}-clang++"
      export CARGO_BUILD_TARGET="aarch64-linux-android"
      export AR="${llvm_prebuilt}/bin/llvm-ar"
      export DTLN_RS_TFLITE_LIB_DIR="${DTLN_RS_TFLITE_LIB_DIR:-${DTLN_RS_BUILD_TREE}/tflite/lib/android/arm64-v8a}"
      ;;
    x86_64)
      export CC="${llvm_prebuilt}/bin/x86_64-linux-android${api}-clang"
      export CXX="${llvm_prebuilt}/bin/x86_64-linux-android${api}-clang++"
      export CARGO_BUILD_TARGET="x86_64-linux-android"
      export AR="${llvm_prebuilt}/bin/llvm-ar"
      export DTLN_RS_TFLITE_LIB_DIR="${DTLN_RS_TFLITE_LIB_DIR:-${DTLN_RS_BUILD_TREE}/tflite/lib/android/x86_64}"
      ;;
    *)
      echo "dtln-rs build: unknown Android ABI ${abi}" >&2
      exit 1
      ;;
  esac
  export CARGO_BUILD_RUSTFLAGS="${DTLN_RS_RUSTFLAGS}"
  export RUSTFLAGS="${DTLN_RS_RUSTFLAGS}"
}

dtln_rs_install_rust_target() {
  local triple="$1"
  if command -v rustup >/dev/null 2>&1; then
    rustup target add "${triple}" 2>/dev/null || true
  fi
}

dtln_rs_ensure_source() {
  if [[ -d "${DTLN_RS_SRC}/.git" ]]; then
    echo "dtln-rs: updating ${DTLN_RS_SRC} (${DTLN_RS_GIT_REF})"
    git -C "${DTLN_RS_SRC}" fetch --depth 1 origin "${DTLN_RS_GIT_REF}" 2>/dev/null || \
      git -C "${DTLN_RS_SRC}" fetch origin
    git -C "${DTLN_RS_SRC}" checkout -B build-ref FETCH_HEAD 2>/dev/null || \
      git -C "${DTLN_RS_SRC}" checkout "${DTLN_RS_GIT_REF}" 2>/dev/null || \
      git -C "${DTLN_RS_SRC}" pull --ff-only
    return 0
  fi

  mkdir -p "$(dirname "${DTLN_RS_SRC}")"
  echo "dtln-rs: cloning ${DTLN_RS_GIT_URL} -> ${DTLN_RS_SRC}"
  git clone --depth 1 --branch "${DTLN_RS_GIT_REF}" "${DTLN_RS_GIT_URL}" "${DTLN_RS_SRC}" 2>/dev/null || \
    git clone --depth 1 "${DTLN_RS_GIT_URL}" "${DTLN_RS_SRC}"
}

# Copy upstream into a build tree and apply three mobile patches + scripts/dtln/extra C FFI.
dtln_rs_prepare_build_tree() {
  if [[ -f "${DTLN_RS_BUILD_TREE}/.dtln-patches-applied" && "${DTLN_RS_FORCE_REPREPARE:-}" != "1" ]]; then
    # Always refresh scripts/dtln/extra (ffi.rs) — incremental builds skip full rsync.
    dtln_rs_apply_mobile_extras
    return 0
  fi
  dtln_rs_ensure_source
  rm -rf "${DTLN_RS_BUILD_TREE}"
  mkdir -p "${DTLN_RS_BUILD_TREE}"
  rsync -a \
    --exclude target \
    --exclude index.node \
    --exclude node_modules \
    "${DTLN_RS_SRC}/" "${DTLN_RS_BUILD_TREE}/"

  local patch_dir="${DTLN_RS_SCRIPT_DIR}/patches"
  if [[ -d "${patch_dir}" ]]; then
    dtln_rs_require_cmd patch
    local patch
    for patch in "${patch_dir}"/*.patch; do
      [[ -f "${patch}" ]] || continue
      echo "dtln-rs: applying $(basename "${patch}")"
      patch -p1 -d "${DTLN_RS_BUILD_TREE}" < "${patch}"
    done
  fi
  dtln_rs_apply_mobile_extras
  touch "${DTLN_RS_BUILD_TREE}/.dtln-patches-applied"
}

# C FFI + sample-rate constant (copied from scripts/dtln/extra; avoids fragile multi-file patches).
dtln_rs_apply_mobile_extras() {
  local extra_src="${DTLN_RS_SCRIPT_DIR}/extra/src"
  if [[ ! -f "${extra_src}/ffi.rs" ]]; then
    return 0
  fi
  cp -f "${extra_src}/ffi.rs" "${DTLN_RS_BUILD_TREE}/src/ffi.rs"
  if ! grep -q 'DTLN_SAMPLE_RATE_HZ' "${DTLN_RS_BUILD_TREE}/src/constants.rs" 2>/dev/null; then
    cat >> "${DTLN_RS_BUILD_TREE}/src/constants.rs" <<'EOF'

/// DTLN models expect 16 kHz mono PCM.
pub const DTLN_SAMPLE_RATE_HZ: usize = 16000;
EOF
  fi
  if ! grep -q 'pub mod ffi;' "${DTLN_RS_BUILD_TREE}/src/lib.rs" 2>/dev/null; then
    if grep -q 'pub mod tflite;' "${DTLN_RS_BUILD_TREE}/src/lib.rs" 2>/dev/null; then
      sed -i.bak '/pub mod tflite;/a\
pub mod ffi;
' "${DTLN_RS_BUILD_TREE}/src/lib.rs"
      rm -f "${DTLN_RS_BUILD_TREE}/src/lib.rs.bak"
    else
      printf '\npub mod ffi;\n' >> "${DTLN_RS_BUILD_TREE}/src/lib.rs"
    fi
  fi
  if ! grep -q 'pub mod ffi;' "${DTLN_RS_BUILD_TREE}/src/lib.rs" 2>/dev/null; then
    echo "dtln-rs: failed to add pub mod ffi to ${DTLN_RS_BUILD_TREE}/src/lib.rs" >&2
    echo "dtln-rs: run DTLN_RS_FORCE_REPREPARE=1 ./utilities/build-dtln-rs.sh ios" >&2
    return 1
  fi
  echo "dtln-rs: applied mobile C FFI (src/ffi.rs)"
}

# True when archive exports _dtln_create (mobile C API).
dtln_rs_archive_exports_c_api() {
  local archive="$1"
  local sym_file
  sym_file="$(mktemp)"
  nm -gU "${archive}" 2>/dev/null >"${sym_file}" || nm "${archive}" 2>/dev/null >"${sym_file}" || true
  if grep -qE '[[:space:]]_dtln_create$' "${sym_file}"; then
    rm -f "${sym_file}"
    return 0
  fi
  rm -f "${sym_file}"
  return 1
}

# Drop cached Rust artifacts so a refreshed ffi.rs is linked into libdtln_rs.a.
dtln_rs_invalidate_rust_staticlib_cache() {
  local triple="$1"
  local profile_dir="release"
  [[ "${DTLN_RS_CARGO_PROFILE}" == "debug" ]] && profile_dir="debug"
  local target_dir="${DTLN_RS_BUILD_TREE}/target"
  local triple_dir="${target_dir}/${triple}/${profile_dir}"
  local rust_lib="${triple_dir}/libdtln_rs.a"
  local ffi_rs="${DTLN_RS_BUILD_TREE}/src/ffi.rs"
  local lib_rs="${DTLN_RS_BUILD_TREE}/src/lib.rs"

  if [[ ! -f "${ffi_rs}" || ! -f "${lib_rs}" ]]; then
    return 0
  fi
  if [[ ! -f "${rust_lib}" || "${ffi_rs}" -nt "${rust_lib}" || "${lib_rs}" -nt "${rust_lib}" ]]; then
    rm -f "${rust_lib}"
    rm -f "${triple_dir}"/deps/libdtln_rs* 2>/dev/null || true
    find "${triple_dir}" -maxdepth 1 -name 'libdtln_rs-*.rlib' -delete 2>/dev/null || true
    echo "dtln-rs: invalidated Rust cache for ${triple} (ffi.rs / lib.rs changed)" >&2
  fi
}

# Canonical install locations under plugins/proton_denoise/third_party/dtln-rs/lib/.
DTLN_RS_INSTALLED_LIBS=(
  "${DTLN_RS_LIB_OUT}/macos/libdtln.a"
  "${DTLN_RS_LIB_OUT}/ios/device/libdtln.a"
  "${DTLN_RS_LIB_OUT}/ios/simulator/libdtln.a"
  "${DTLN_RS_LIB_OUT}/android/armeabi-v7a/libdtln.a"
  "${DTLN_RS_LIB_OUT}/android/arm64-v8a/libdtln.a"
  "${DTLN_RS_LIB_OUT}/android/x86_64/libdtln.a"
)

# Remove obsolete per-arch placeholder paths; verify real libs landed in third_party.
# Optional args: only verify these lib paths (default: full DTLN_RS_INSTALLED_LIBS list).
dtln_rs_finalize_third_party_install() {
  local lib min_bytes=1000000
  local -a required
  if [[ "$#" -gt 0 ]]; then
    required=("$@")
  else
    required=("${DTLN_RS_INSTALLED_LIBS[@]}")
  fi
  echo "dtln-rs: finalizing install under ${DTLN_RS_THIRD_PARTY}"

  local legacy
  for legacy in \
    "${DTLN_RS_LIB_OUT}/macos/arm64" \
    "${DTLN_RS_LIB_OUT}/macos/x86_64" \
    "${DTLN_RS_LIB_OUT}/ios/device-arm64" \
    "${DTLN_RS_LIB_OUT}/ios/simulator-arm64" \
    "${DTLN_RS_LIB_OUT}/ios/simulator-x86_64"
  do
    if [[ -e "${legacy}" ]]; then
      rm -rf "${legacy}"
      echo "dtln-rs: removed legacy path ${legacy}"
    fi
  done

  local missing=0
  for lib in "${required[@]}"; do
    if [[ ! -f "${lib}" ]]; then
      echo "dtln-rs: missing ${lib}" >&2
      missing=$((missing + 1))
      continue
    fi
    local size
    size="$(wc -c < "${lib}" | tr -d ' ')"
    if [[ "${size}" -lt "${min_bytes}" ]]; then
      echo "dtln-rs: ${lib} looks like a placeholder (${size} bytes)" >&2
      missing=$((missing + 1))
      continue
    fi
    if command -v lipo >/dev/null 2>&1; then
      echo "dtln-rs: $(basename "$(dirname "${lib}")")/$(basename "${lib}") — $(ls -lh "${lib}" | awk '{print $5}')"
      lipo -info "${lib}" 2>/dev/null || true
    else
      ls -lh "${lib}"
    fi
  done

  if [[ "${missing}" -gt 0 ]]; then
    echo "dtln-rs: install incomplete — run ./plugins/proton_denoise/scripts/dtln/build-dtln-rs.sh apple (and android when TFLite is ready)" >&2
    return 1
  fi
  echo "dtln-rs: all expected libraries installed under ${DTLN_RS_LIB_OUT}"
}

# macOS-only: upstream ships osx prebuilt TFLite tarballs (wrong platform for iOS slices).
dtln_rs_extract_tflite_prebuilt() {
  local arch="$1"
  local tflite_dir="${DTLN_RS_BUILD_TREE}/tflite"
  mkdir -p "${tflite_dir}"

  case "${arch}" in
    arm64|aarch64)
      tar -xjf "${tflite_dir}/tflite-prebuilt.osx.arm64.tar.bz2" -C "${tflite_dir}"
      ;;
    x86_64|x64)
      tar -xjf "${tflite_dir}/tflite-prebuilt.osx.x64.tar.bz2" -C "${tflite_dir}"
      ;;
    *)
      echo "dtln-rs: no prebuilt TFLite tarball for arch ${arch}; build tflite via cmake in tflite/" >&2
      if [[ -f "${tflite_dir}/CMakeLists.txt" || -f "${tflite_dir}/CMakeLists.txt.in" ]]; then
        dtln_rs_require_cmd cmake
        cmake -S "${tflite_dir}" -B "${tflite_dir}/build" -DCMAKE_BUILD_TYPE=Release
        cmake --build "${tflite_dir}/build" --config Release
      fi
      ;;
  esac
  export DTLN_RS_TFLITE_LIB_DIR="${tflite_dir}/lib"
}

dtln_rs_cargo_static_lib() {
  local triple="$1"
  local profile="${DTLN_RS_CARGO_PROFILE}"
  local profile_dir="release"
  [[ "${profile}" == "debug" ]] && profile_dir="debug"
  local target_dir="${DTLN_RS_BUILD_TREE}/target"

  # Subshell logs go to stderr — stdout is only the final archive path (see rust_lib= capture).
  (
    cd "${DTLN_RS_BUILD_TREE}"
    export CARGO_TARGET_DIR="${target_dir}"
    # Use CARGO_TARGET_*_RUSTFLAGS from dtln_rs_export_apple_cc_env for iOS link args;
    # do not set global RUSTFLAGS (breaks cxx build scripts with duplicate -arch).
    unset RUSTFLAGS
    if [[ -n "${DTLN_RS_ANDROID_ABI:-}" ]]; then
      export RUSTFLAGS="${CARGO_BUILD_RUSTFLAGS:-} -C strip=symbols"
    fi
    dtln_rs_invalidate_rust_staticlib_cache "${triple}"
    cargo build \
      --profile "${profile}" \
      --target "${triple}" \
      --lib \
      -p dtln-rs \
      --no-default-features
  ) >&2

  local rust_lib="${target_dir}/${triple}/${profile_dir}/libdtln_rs.a"
  if [[ ! -f "${rust_lib}" ]]; then
    rust_lib="$(find "${target_dir}/${triple}/${profile_dir}" -maxdepth 1 -name 'libdtln*.a' -print 2>/dev/null | head -1)"
  fi
  if [[ ! -f "${rust_lib}" ]]; then
    echo "dtln-rs: expected static lib under ${target_dir}/${triple}/${profile_dir}/" >&2
    exit 1
  fi
  echo "${rust_lib}"
}

dtln_rs_ndk_tool() {
  local tool="$1"
  dtln_rs_resolve_ndk
  local prebuilt ar_bin
  prebuilt="$(dtln_rs_ndk_llvm_prebuilt)"
  ar_bin="${prebuilt}/bin/${tool}"
  if [[ ! -x "${ar_bin}" ]]; then
    echo "dtln-rs: NDK tool missing: ${ar_bin}" >&2
    return 1
  fi
  echo "${ar_bin}"
}

# Merge ELF static libs by extracting member objects (avoids nesting whole .a files).
dtln_rs_merge_static_libs_elf_objects() {
  local out="$1"
  shift
  local ar_bin tmpdir obj_count
  ar_bin="$(dtln_rs_ndk_tool llvm-ar)" || return 1
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/dtln-merge.XXXXXX")"
  local objects_dir="${tmpdir}/objects"
  mkdir -p "${objects_dir}"
  local lib lib_base lib_tag extract_dir obj
  for lib in "$@"; do
    lib_base="$(basename "${lib}" .a)"
    lib_tag="${lib_base}_$(printf '%s' "${lib}" | shasum -a 256 | cut -c1-8)"
    extract_dir="${tmpdir}/extract/${lib_tag}"
    mkdir -p "${extract_dir}"
    (cd "${extract_dir}" && "${ar_bin}" x "${lib}")
    for obj in "${extract_dir}"/*.o; do
      [[ -f "${obj}" ]] || continue
      cp -f "${obj}" "${objects_dir}/${lib_tag}__$(basename "${obj}")"
    done
  done
  obj_count="$(find "${objects_dir}" -name '*.o' 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "${obj_count}" -eq 0 ]]; then
    echo "dtln-rs: no object files to merge into ${out}" >&2
    rm -rf "${tmpdir}"
    return 1
  fi
  rm -f "${out}"
  local rsp="${tmpdir}/objects.rsp"
  find "${objects_dir}" -name '*.o' -type f 2>/dev/null | sort > "${rsp}"
  if [[ ! -s "${rsp}" ]]; then
    echo "dtln-rs: no object paths for ${out}" >&2
    rm -rf "${tmpdir}"
    return 1
  fi
  "${ar_bin}" crs "${out}" @"${rsp}"
  "${ar_bin}" s "${out}" 2>/dev/null || true
  rm -rf "${tmpdir}"
}

dtln_rs_strip_elf_static_lib() {
  local lib_path="$1"
  local strip_bin
  strip_bin="$(dtln_rs_ndk_tool llvm-strip)" || return 0
  "${strip_bin}" --strip-unneeded "${lib_path}" 2>/dev/null || true
}

# Android: merge Rust + TFLite static libs into one libdtln.a via relocatable link (-r).
# Avoids llvm-ar object-name collisions (e.g. duplicate common.cc.o members).
dtln_rs_merge_android_libdtln() {
  local out="$1"
  local rust_lib="$2"
  shift 2
  local cxx_bin ar_bin tmp_o rsp
  cxx_bin="${CXX:?dtln-rs: CXX not set — call dtln_rs_android_ndk_env first}"
  ar_bin="$(dtln_rs_ndk_tool llvm-ar)" || return 1

  tmp_stamp="$(mktemp "${TMPDIR:-/tmp}/dtln-merge.XXXXXX")"
  rm -f "${tmp_stamp}"
  tmp_o="${tmp_stamp}.o"
  rsp="$(mktemp "${TMPDIR:-/tmp}/dtln-libs.XXXXXX")"
  {
    echo "-Wl,--allow-multiple-definition"
    echo "-Wl,--whole-archive"
    printf '%s\n' "${rust_lib}" "$@"
    echo "-Wl,--no-whole-archive"
  } > "${rsp}"

  echo "dtln-rs: relocatable merge ($(wc -l < "${rsp}" | tr -d ' ') inputs) -> ${out}"
  "${cxx_bin}" -r -nostdlib++ -nostdlib -o "${tmp_o}" @"${rsp}"

  local strip_bin
  strip_bin="$(dtln_rs_ndk_tool llvm-strip)" || true
  if [[ -n "${strip_bin}" && -x "${strip_bin}" ]]; then
    "${strip_bin}" --strip-unneeded "${tmp_o}" 2>/dev/null || true
  fi

  mkdir -p "$(dirname "${out}")"
  rm -f "${out}"
  "${ar_bin}" crs "${out}" "${tmp_o}"
  "${ar_bin}" s "${out}" 2>/dev/null || true
  rm -f "${tmp_o}" "${rsp}"
}

# Apple (iOS / iOS sim): relocatable merge — same model as Android.
# libtool -static keeps only one member per .o basename across 80+ TFLite archives,
# which loses Abseil symbols; force-loading the libtool output then hits ~2k dupes.
dtln_rs_merge_apple_libdtln() {
  local out="$1"
  shift
  local cxx_bin ar_bin tmp_o rsp
  cxx_bin="${CXX:?dtln-rs: CXX not set — call dtln_rs_export_apple_cc_env first}"
  dtln_rs_require_cmd xcrun
  ar_bin="$(xcrun --find llvm-ar)"

  tmp_stamp="$(mktemp "${TMPDIR:-/tmp}/dtln-merge.XXXXXX")"
  rm -f "${tmp_stamp}"
  tmp_o="${tmp_stamp}.o"
  rsp="$(mktemp "${TMPDIR:-/tmp}/dtln-libs.XXXXXX")"
  {
    echo "-Wl,-multiply_defined,suppress"
    echo "-Wl,-all_load"
    printf '%s\n' "$@"
  } > "${rsp}"

  echo "dtln-rs: Apple relocatable merge ($(wc -l < "${rsp}" | tr -d ' ') inputs) -> ${out}"
  _cxxflags="${CXXFLAGS:-}"
  # nosemgrep
  # shellcheck disable=SC2086
  "${cxx_bin}" ${_cxxflags} -r -nostdlib++ -nostdlib -o "${tmp_o}" @"${rsp}"

  mkdir -p "$(dirname "${out}")"
  rm -f "${out}"
  "${ar_bin}" crs "${out}" "${tmp_o}"
  "${ar_bin}" s "${out}" 2>/dev/null || true
  rm -f "${tmp_o}" "${rsp}"
}

# Runtime TFLite archives from a cmake build tree (excludes protoc/protobuf/benchmarks).
dtln_rs_collect_tflite_cmake_archives() {
  local cmake_build="$1"
  if [[ ! -d "${cmake_build}" ]]; then
    echo "dtln-rs: missing TFLite cmake build at ${cmake_build}" >&2
    return 1
  fi
  local lib base
  while IFS= read -r lib; do
    base="$(basename "${lib}")"
    if dtln_rs_should_skip_tflite_archive "${base}"; then
      continue
    fi
    printf '%s\n' "${lib}"
  done < <(find "${cmake_build}" -name '*.a' -type f 2>/dev/null | sort)
}

dtln_rs_collect_tflite_android_cmake_archives() {
  local abi="$1"
  dtln_rs_collect_tflite_cmake_archives "${DTLN_RS_TFLITE_ANDROID_CACHE}/${abi}/cmake-build"
}

dtln_rs_collect_tflite_apple_cmake_archives() {
  local platform="$1"
  local arch="$2"
  dtln_rs_collect_tflite_cmake_archives "${DTLN_RS_TFLITE_APPLE_CACHE}/${platform}-${arch}/cmake-build"
}

# Legacy single-archive helper (tensorflow-lite only — insufficient for Android link).
dtln_rs_tflite_android_runtime_lib() {
  local lib_dir="$1"
  local primary="${lib_dir}/libtensorflow-lite.a"
  if [[ ! -f "${primary}" ]]; then
    echo "dtln-rs: missing ${primary}" >&2
    return 1
  fi
  echo "${primary}"
}

dtln_rs_should_skip_tflite_archive() {
  local name="$1"
  case "${name}" in
    libprotoc.a | libprotobuf.a)
      return 0
      ;;
    libcpuinfo_internals.a)
      return 0
      ;;
  esac
  [[ "${name}" == *benchmark* ]] && return 0
  return 1
}

dtln_rs_ndk_llvm_prebuilt() {
  local host_tag llvm_prebuilt
  case "$(uname -s)/$(uname -m)" in
    Darwin/arm64) host_tag="darwin-arm64" ;;
    Darwin/x86_64) host_tag="darwin-x86_64" ;;
    Linux/x86_64) host_tag="linux-x86_64" ;;
    Linux/aarch64) host_tag="linux-aarch64" ;;
    *) host_tag="darwin-x86_64" ;;
  esac
  llvm_prebuilt="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/${host_tag}"
  if [[ ! -d "${llvm_prebuilt}" ]]; then
    case "${host_tag}" in
      darwin-arm64) llvm_prebuilt="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/darwin-x86_64" ;;
      linux-aarch64) llvm_prebuilt="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64" ;;
    esac
  fi
  echo "${llvm_prebuilt}"
}

dtln_rs_merge_static_libs() {
  local out="$1"
  shift
  mkdir -p "$(dirname "${out}")"

  # Android / Linux ELF archives: never use macOS libtool.
  if [[ -n "${DTLN_RS_ANDROID_ABI:-}" ]]; then
    dtln_rs_merge_static_libs_elf_objects "${out}" "$@"
    return 0
  fi

  if command -v libtool >/dev/null 2>&1; then
    libtool -static -o "${out}" "$@"
    return 0
  fi
  dtln_rs_merge_static_libs_elf "${out}" "$@"
}

dtln_rs_collect_tflite_archives() {
  local lib_dir="${DTLN_RS_TFLITE_LIB_DIR:-}"
  if [[ -z "${lib_dir}" ]]; then
    lib_dir="${DTLN_RS_BUILD_TREE}/tflite/lib"
  fi
  if [[ ! -d "${lib_dir}" ]]; then
    return 0
  fi
  # Android / iOS cmake builds install one self-contained runtime archive.
  # macOS prebuilt tarballs ship libtensorflow-lite.a plus many dependent *.a.
  if [[ -f "${lib_dir}/libtensorflow-lite.a" ]]; then
    local archive_count
    archive_count="$(find "${lib_dir}" -maxdepth 1 -name '*.a' 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "${archive_count}" -le 1 ]]; then
      echo "${lib_dir}/libtensorflow-lite.a"
      return 0
    fi
  fi
  # Never fall back to the macOS prebuilt tarball tree during iOS cross-builds.
  if [[ "${lib_dir}" == *"/tflite/lib/ios/"* ]]; then
    return 0
  fi
  find "${lib_dir}" -maxdepth 1 -name "*.a" -print 2>/dev/null
}

# TensorFlow Lite tag aligned with Meet video_effects (2.17.0).
DTLN_RS_TFLITE_GIT_TAG="${DTLN_RS_TFLITE_GIT_TAG:-v2.17.0}"
DTLN_RS_TFLITE_SRC="${DTLN_RS_TFLITE_SRC:-${DTLN_RS_ROOT}/.local/tensorflow-lite-src}"
DTLN_RS_TFLITE_ANDROID_CACHE="${DTLN_RS_TFLITE_ANDROID_CACHE:-${DTLN_RS_ROOT}/.local/dtln-rs-tflite-android}"
DTLN_RS_TFLITE_APPLE_CACHE="${DTLN_RS_TFLITE_APPLE_CACHE:-${DTLN_RS_ROOT}/.local/dtln-rs-tflite-apple}"

# Xcode 16+ rejects std::abs<float> as std::function argument in elementwise.cc.
dtln_rs_patch_tflite_apple_source() {
  local elementwise="${DTLN_RS_TFLITE_SRC}/tensorflow/lite/kernels/elementwise.cc"
  [[ -f "${elementwise}" ]] || return 0
  if grep -q 'static_cast<float (\*)(float)>(std::abs)' "${elementwise}" 2>/dev/null; then
    return 0
  fi
  sed -i.bak \
    -e 's/EvalImpl<float>(context, node, std::abs<float>, type)/EvalImpl<float>(context, node, static_cast<float (*)(float)>(std::abs), type)/' \
    -e 's/EvalImpl<int32_t>(context, node, std::abs<int32_t>, type)/EvalImpl<int32_t>(context, node, static_cast<int32_t (*)(int32_t)>(std::abs), type)/' \
    "${elementwise}"
  rm -f "${elementwise}.bak"
  echo "dtln-rs: patched TensorFlow Lite elementwise.cc for Apple cross-builds"
}

dtln_rs_ensure_tflite_source() {
  if [[ -f "${DTLN_RS_TFLITE_SRC}/tensorflow/lite/CMakeLists.txt" ]]; then
    dtln_rs_patch_tflite_apple_source
    return 0
  fi
  if [[ -e "${DTLN_RS_TFLITE_SRC}" && ! -f "${DTLN_RS_TFLITE_SRC}/tensorflow/lite/CMakeLists.txt" ]]; then
    echo "dtln-rs: removing incomplete TensorFlow checkout at ${DTLN_RS_TFLITE_SRC}" >&2
    rm -rf "${DTLN_RS_TFLITE_SRC}"
  fi
  mkdir -p "$(dirname "${DTLN_RS_TFLITE_SRC}")"
  echo "dtln-rs: cloning TensorFlow ${DTLN_RS_TFLITE_GIT_TAG} for TFLite cross-builds"
  git clone --depth 1 --branch "${DTLN_RS_TFLITE_GIT_TAG}" \
    https://github.com/tensorflow/tensorflow.git "${DTLN_RS_TFLITE_SRC}"
  dtln_rs_patch_tflite_apple_source
}

# Back-compat alias.
dtln_rs_ensure_tflite_android_source() {
  dtln_rs_ensure_tflite_source
}

# Build (or reuse) all TFLite *.a for one ABI under ${DTLN_RS_BUILD_TREE}/tflite/lib/android/<abi>/.
dtln_rs_build_tflite_android() {
  local abi="$1"
  dtln_rs_resolve_ndk
  dtln_rs_require_cmd cmake
  dtln_rs_require_cmd git

  local out_lib_dir="${DTLN_RS_BUILD_TREE}/tflite/lib/android/${abi}"
  local marker="${out_lib_dir}/.tflite-built"
  if [[ -f "${marker}" ]]; then
    local count
    count="$(find "${out_lib_dir}" -maxdepth 1 -name '*.a' 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "${count}" -gt 0 ]]; then
      echo "dtln-rs: reusing Android TFLite libs for ${abi} (${count} archives)"
      export DTLN_RS_TFLITE_LIB_DIR="${out_lib_dir}"
      return 0
    fi
  fi

  dtln_rs_ensure_tflite_android_source

  local cmake_build="${DTLN_RS_TFLITE_ANDROID_CACHE}/${abi}/cmake-build"
  mkdir -p "${cmake_build}" "${out_lib_dir}"

  local jobs="${DTLN_RS_BUILD_JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)}"

  echo "dtln-rs: configuring TensorFlow Lite for Android ${abi}"
  cmake -S "${DTLN_RS_TFLITE_SRC}/tensorflow/lite" -B "${cmake_build}" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_TOOLCHAIN_FILE="${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="${abi}" \
    -DANDROID_PLATFORM=android-24 \
    -DCMAKE_BUILD_TYPE=Release \
    -DTFLITE_ENABLE_XNNPACK=ON \
    -DTFLITE_ENABLE_GPU=OFF

  echo "dtln-rs: building TensorFlow Lite for Android ${abi} (this can take a while)"
  # Build only the core library; full 'all' pulls benchmark/profiling protos that need host protobuf.
  cmake --build "${cmake_build}" --config Release --target tensorflow-lite -j"${jobs}"

  rm -f "${out_lib_dir}"/*.a
  local tflite_a
  tflite_a="$(find "${cmake_build}" -name 'libtensorflow-lite.a' -type f 2>/dev/null | head -1)"
  if [[ -z "${tflite_a}" || ! -f "${tflite_a}" ]]; then
    echo "dtln-rs: libtensorflow-lite.a not found under ${cmake_build}" >&2
    exit 1
  fi
  cp -f "${tflite_a}" "${out_lib_dir}/libtensorflow-lite.a"

  touch "${marker}"
  echo "dtln-rs: installed runtime TFLite for ${abi} -> ${out_lib_dir}/libtensorflow-lite.a ($(ls -lh "${out_lib_dir}/libtensorflow-lite.a" | awk '{print $5}'))"
  export DTLN_RS_TFLITE_LIB_DIR="${out_lib_dir}"
}

# Build TensorFlow Lite for iphoneos / iphonesimulator (must not use osx prebuilt tarballs).
dtln_rs_build_tflite_apple() {
  local platform="$1"
  local arch="$2"

  dtln_rs_require_cmd xcrun
  dtln_rs_require_cmd cmake
  dtln_rs_require_cmd git

  local out_lib_dir="${DTLN_RS_BUILD_TREE}/tflite/lib/ios/${platform}-${arch}"
  local marker="${out_lib_dir}/.tflite-built"
  if [[ -f "${marker}" && -f "${out_lib_dir}/libtensorflow-lite.a" ]]; then
    echo "dtln-rs: reusing Apple TFLite for ${platform}/${arch}"
    export DTLN_RS_TFLITE_LIB_DIR="${out_lib_dir}"
    return 0
  fi

  dtln_rs_ensure_tflite_source
  dtln_rs_patch_tflite_apple_source

  local sdk sysroot deploy_target target_triple
  export IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-15.0}"
  deploy_target="${IPHONEOS_DEPLOYMENT_TARGET}"

  case "${platform}" in
    iphoneos)
      sdk="iphoneos"
      case "${arch}" in
        arm64) target_triple="arm64-apple-ios${deploy_target}" ;;
        *)
          echo "dtln-rs: unsupported iphoneos arch ${arch}" >&2
          return 1
          ;;
      esac
      ;;
    iphonesimulator)
      sdk="iphonesimulator"
      case "${arch}" in
        arm64) target_triple="arm64-apple-ios${deploy_target}-simulator" ;;
        x86_64) target_triple="x86_64-apple-ios${deploy_target}-simulator" ;;
        *)
          echo "dtln-rs: unsupported iphonesimulator arch ${arch}" >&2
          return 1
          ;;
      esac
      ;;
    *)
      echo "dtln-rs: dtln_rs_build_tflite_apple expects iphoneos|iphonesimulator, got ${platform}" >&2
      return 1
      ;;
  esac

  sysroot="$(xcrun --sdk "${sdk}" --show-sdk-path)"
  local cmake_build="${DTLN_RS_TFLITE_APPLE_CACHE}/${platform}-${arch}/cmake-build"
  mkdir -p "${cmake_build}" "${out_lib_dir}"

  local jobs="${DTLN_RS_BUILD_JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)}"
  # Do not set CMAKE_SYSTEM_NAME=iOS — flatbuffers' flatc install rules fail on bundle
  # destinations. Cross-compile via iphoneos/iphonesimulator sysroot + -target instead.
  if [[ ! -f "${cmake_build}/CMakeCache.txt" ]]; then
    rm -rf "${cmake_build}"
    echo "dtln-rs: configuring TensorFlow Lite for ${platform}/${arch}"
    cmake -S "${DTLN_RS_TFLITE_SRC}/tensorflow/lite" -B "${cmake_build}" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_OSX_SYSROOT="${sysroot}" \
    -DCMAKE_OSX_ARCHITECTURES="${arch}" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="${deploy_target}" \
    -DCMAKE_C_FLAGS="-target ${target_triple} -isysroot ${sysroot}" \
    -DCMAKE_CXX_FLAGS="-target ${target_triple} -isysroot ${sysroot}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_STANDARD=17 \
    -DCMAKE_CXX_STANDARD_REQUIRED=ON \
    -DCMAKE_MACOSX_BUNDLE=OFF \
    -DFLATBUFFERS_BUILD_FLATC=OFF \
    -DTFLITE_ENABLE_XNNPACK=OFF \
    -DTFLITE_ENABLE_GPU=OFF
  else
    echo "dtln-rs: reusing TensorFlow Lite cmake tree for ${platform}/${arch}"
  fi

  echo "dtln-rs: building TensorFlow Lite for ${platform}/${arch} (this can take a while)"
  cmake --build "${cmake_build}" --config Release --target tensorflow-lite -j"${jobs}"

  rm -f "${out_lib_dir}"/*.a
  local tflite_a
  tflite_a="$(find "${cmake_build}" -name 'libtensorflow-lite.a' -type f 2>/dev/null | head -1)"
  if [[ -z "${tflite_a}" || ! -f "${tflite_a}" ]]; then
    echo "dtln-rs: libtensorflow-lite.a not found under ${cmake_build}" >&2
    return 1
  fi
  cp -f "${tflite_a}" "${out_lib_dir}/libtensorflow-lite.a"
  touch "${marker}"
  echo "dtln-rs: installed Apple TFLite for ${platform}/${arch} -> ${out_lib_dir}/libtensorflow-lite.a"
  export DTLN_RS_TFLITE_LIB_DIR="${out_lib_dir}"
}

# LC_BUILD_VERSION.platform: 1=macOS, 2=iOS, 7=iOS Simulator
dtln_rs_expected_apple_platform() {
  case "$1" in
    macosx) echo 1 ;;
    iphoneos) echo 2 ;;
    iphonesimulator) echo 7 ;;
    *)
      echo "dtln-rs: unknown Apple platform $1" >&2
      return 1
      ;;
  esac
}

# First extractable member for platform checks (merged TFLite uses one relocatable .o).
dtln_rs_ar_pick_verify_member() {
  local lib="$1"
  local ar_bin member
  if command -v xcrun >/dev/null 2>&1; then
    ar_bin="$(xcrun --find llvm-ar 2>/dev/null || true)"
  fi
  ar_bin="${ar_bin:-ar}"
  if "${ar_bin}" -t "${lib}" 2>/dev/null | grep -F 'city.cc.o' >/dev/null 2>&1; then
    echo "city.cc.o"
    return 0
  fi
  member="$("${ar_bin}" -t "${lib}" 2>/dev/null | grep -E '\.o$' | sed -n '1p' || true)"
  if [[ -z "${member}" ]]; then
    member="$("${ar_bin}" -t "${lib}" 2>/dev/null | sed -n '1p' || true)"
  fi
  if [[ -z "${member}" ]]; then
    return 1
  fi
  echo "${member}"
}

dtln_rs_verify_apple_archive_platform() {
  local lib="$1"
  local platform_name="$2"
  local expected ar_bin
  expected="$(dtln_rs_expected_apple_platform "${platform_name}")"

  dtln_rs_require_cmd otool
  local tmpdir member actual
  tmpdir="$(mktemp -d)"
  member="$(dtln_rs_ar_pick_verify_member "${lib}")" || {
    rm -rf "${tmpdir}"
    echo "dtln-rs: cannot verify ${lib} — no object members" >&2
    return 1
  }
  if command -v xcrun >/dev/null 2>&1; then
    ar_bin="$(xcrun --find llvm-ar 2>/dev/null || true)"
  fi
  ar_bin="${ar_bin:-ar}"
  (
    cd "${tmpdir}"
    "${ar_bin}" -x "${lib}" "${member}"
  )
  actual="$(otool -l "${tmpdir}/${member}" 2>/dev/null | awk '/platform / {print $2; exit}')"
  rm -rf "${tmpdir}"
  if [[ -z "${actual}" ]]; then
    echo "dtln-rs: cannot read LC_BUILD_VERSION.platform from ${lib} (${member})" >&2
    return 1
  fi
  if [[ "${actual}" != "${expected}" ]]; then
    echo "dtln-rs: ${lib} has platform ${actual}, expected ${expected} for ${platform_name}" >&2
    echo "dtln-rs: rebuild with ./plugins/proton_denoise/scripts/dtln/build-dtln-rs.sh ios (do not merge macOS TFLite into iOS libs)" >&2
    return 1
  fi
}

dtln_rs_install_lib() {
  local dest="$1"
  local built="$2"
  mkdir -p "$(dirname "${dest}")"
  cp -f "${built}" "${dest}"
  echo "dtln-rs: installed ${dest}"
}

dtln_rs_triple_to_cargo_env() {
  native_triple_to_cargo_env "$@"
}

dtln_rs_export_apple_cc_env() {
  native_export_apple_cc_env "$1" "${DTLN_RS_RUSTFLAGS:-}"
}

# Sets globals: DTLN_SLICE_TRIPLE, DTLN_SLICE_TFLITE_ARCH
dtln_rs_apple_slice_config() {
  local platform="$1"
  local arch="$2"

  case "${platform}:${arch}" in
    macosx:arm64)
      DTLN_SLICE_TRIPLE="aarch64-apple-darwin"
      DTLN_SLICE_TFLITE_ARCH="arm64"
      ;;
    macosx:x86_64)
      DTLN_SLICE_TRIPLE="x86_64-apple-darwin"
      DTLN_SLICE_TFLITE_ARCH="x86_64"
      ;;
    iphoneos:arm64)
      DTLN_SLICE_TRIPLE="aarch64-apple-ios"
      DTLN_SLICE_TFLITE_ARCH="arm64"
      ;;
    iphonesimulator:arm64)
      DTLN_SLICE_TRIPLE="aarch64-apple-ios-sim"
      DTLN_SLICE_TFLITE_ARCH="arm64"
      ;;
    iphonesimulator:x86_64)
      DTLN_SLICE_TRIPLE="x86_64-apple-ios"
      DTLN_SLICE_TFLITE_ARCH="x86_64"
      ;;
    *)
      echo "dtln-rs: unsupported Apple slice ${platform}/${arch}" >&2
      return 1
      ;;
  esac
}

# Build one platform/arch slice into a single libdtln.a (Rust + TFLite merged).
dtln_rs_build_apple_slice() {
  local platform="$1"
  local arch="$2"
  local out_lib="$3"

  dtln_rs_apple_slice_config "${platform}" "${arch}"

  dtln_rs_install_rust_target "${DTLN_SLICE_TRIPLE}"
  case "${platform}" in
    macosx)
      dtln_rs_extract_tflite_prebuilt "${DTLN_SLICE_TFLITE_ARCH}"
      ;;
    iphoneos | iphonesimulator)
      dtln_rs_build_tflite_apple "${platform}" "${arch}" || return 1
      ;;
    *)
      echo "dtln-rs: unsupported Apple platform ${platform}" >&2
      return 1
      ;;
  esac
  dtln_rs_export_apple_cc_env "${DTLN_SLICE_TRIPLE}"

  local rust_lib
  rust_lib="$(dtln_rs_cargo_static_lib "${DTLN_SLICE_TRIPLE}")"

  local tflite_libs=()
  local _tflite_lib
  if [[ "${platform}" == iphoneos || "${platform}" == iphonesimulator ]]; then
    while IFS= read -r _tflite_lib; do
      [[ -n "${_tflite_lib}" ]] && tflite_libs+=("${_tflite_lib}")
    done < <(dtln_rs_collect_tflite_apple_cmake_archives "${platform}" "${arch}")
  else
    while IFS= read -r _tflite_lib; do
      [[ -n "${_tflite_lib}" ]] && tflite_libs+=("${_tflite_lib}")
    done < <(dtln_rs_collect_tflite_archives)
  fi

  if [[ ${#tflite_libs[@]} -eq 0 ]]; then
    if [[ "${platform}" == iphoneos || "${platform}" == iphonesimulator || "${platform}" == macosx ]]; then
      echo "dtln-rs: no TFLite archives for ${platform}/${arch}" >&2
      return 1
    fi
    echo "dtln-rs: warning — no tflite/lib/*.a for ${platform}/${arch}" >&2
  else
    echo "dtln-rs: Rust + ${#tflite_libs[@]} TFLite archives for ${platform}/${arch}"
  fi

  local tmp_out tflite_out
  tmp_out="$(mktemp "${TMPDIR:-/tmp}/libdtln-slice.XXXXXX")"
  if [[ "${platform}" == macosx ]]; then
    # Single libdtln.a (Rust + TFLite) for macOS archive/OOTB — cargo does not embed TFLite.
    local merge_inputs=("${rust_lib}")
    if [[ ${#tflite_libs[@]} -gt 0 ]]; then
      merge_inputs+=("${tflite_libs[@]}")
    fi
    dtln_rs_merge_apple_libdtln "${tmp_out}" "${merge_inputs[@]}"
  elif [[ "${platform}" == iphoneos || "${platform}" == iphonesimulator ]]; then
    # Rust-only libdtln.a: safe to force_load at app link (no embedded TFLite).
    # TFLite runtime is libdtln_tflite.a — pod force_load only (collides with MediaPipe).
    cp -f "${rust_lib}" "${tmp_out}"
    if ! dtln_rs_archive_exports_c_api "${tmp_out}"; then
      echo "dtln-rs: Rust slice missing _dtln_create for ${platform}/${arch} (${rust_lib})" >&2
      echo "dtln-rs: retry — DTLN_RS_FORCE_REPREPARE=1 ./utilities/build-dtln-rs.sh ios" >&2
      return 1
    fi
    if [[ ${#tflite_libs[@]} -gt 0 ]]; then
      tflite_out="$(dirname "${out_lib}")/libdtln_tflite.a"
      dtln_rs_merge_apple_libdtln "${tflite_out}" "${tflite_libs[@]}"
      dtln_rs_verify_apple_archive_platform "${tflite_out}" "${platform}" || return 1
      echo "dtln-rs: built TFLite runtime ${tflite_out}"
    fi
  else
    local merge_args=("${rust_lib}")
    if [[ ${#tflite_libs[@]} -gt 0 ]]; then
      merge_args+=("${tflite_libs[@]}")
    fi
    dtln_rs_merge_static_libs "${tmp_out}" "${merge_args[@]}"
  fi
  dtln_rs_verify_apple_archive_platform "${tmp_out}" "${platform}" || return 1
  dtln_rs_install_lib "${out_lib}" "${tmp_out}"
  rm -f "${tmp_out}"
}

# Create a fat/universal static library from per-arch slices (macOS / iphonesimulator).
dtln_rs_lipo_fat() {
  local out_fat="$1"
  shift
  dtln_rs_require_cmd lipo
  mkdir -p "$(dirname "${out_fat}")"
  if [[ "$#" -eq 1 ]]; then
    cp -f "$1" "${out_fat}"
    echo "dtln-rs: installed single-arch ${out_fat}"
    return 0
  fi
  lipo -create "$@" -output "${out_fat}"
  lipo -info "${out_fat}"
  echo "dtln-rs: installed fat ${out_fat}"
}
