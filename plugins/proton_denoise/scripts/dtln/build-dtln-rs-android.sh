#!/usr/bin/env bash
# Cross-compile libdtln.a for one Android ABI (Meet: armeabi-v7a, arm64-v8a, x86_64).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=build-dtln-rs-env.sh
source "${SCRIPT_DIR}/build-dtln-rs-env.sh"

usage() {
  cat <<'EOF' >&2
Usage: build-dtln-rs-android.sh <abi> [output_libdtln.a]

  abi   armeabi-v7a | arm64-v8a | x86_64

Produces one merged libdtln.a (~40 MB/arm64): Rust staticlib + all TFLite runtime
archives, same packaging model as iOS (single check-in artifact per ABI).
EOF
  exit 1
}

ABI="${1:-}"
OUT="${2:-}"
[[ -n "${ABI}" ]] || usage

dtln_rs_resolve_rust
if [[ "${DTLN_RS_SKIP_PREPARE:-}" != "1" ]]; then
  dtln_rs_prepare_build_tree
fi
dtln_rs_android_ndk_env "${ABI}"
dtln_rs_build_tflite_android "${ABI}"

case "${ABI}" in
  armeabi-v7a)
    OUT_DEFAULT="${DTLN_RS_LIB_OUT}/android/armeabi-v7a/libdtln.a"
    ;;
  arm64-v8a)
    OUT_DEFAULT="${DTLN_RS_LIB_OUT}/android/arm64-v8a/libdtln.a"
    ;;
  x86_64)
    OUT_DEFAULT="${DTLN_RS_LIB_OUT}/android/x86_64/libdtln.a"
    ;;
  *)
    usage
    ;;
esac
OUT="${OUT:-${OUT_DEFAULT}}"
DEPS_DIR="$(dirname "${OUT}")/deps"

dtln_rs_install_rust_target "${CARGO_BUILD_TARGET}"

RUST_LIB="$(dtln_rs_cargo_static_lib "${CARGO_BUILD_TARGET}")"
rust_size="$(ls -lh "${RUST_LIB}" | awk '{print $5}')"
echo "dtln-rs: Rust staticlib ${rust_size}"

TFLITE_LIBS=()
while IFS= read -r _tflite_lib; do
  [[ -n "${_tflite_lib}" ]] && TFLITE_LIBS+=("${_tflite_lib}")
done < <(dtln_rs_collect_tflite_android_cmake_archives "${ABI}")
if [[ ${#TFLITE_LIBS[@]} -eq 0 ]]; then
  echo "dtln-rs: no TFLite runtime archives for ${ABI}" >&2
  exit 1
fi
echo "dtln-rs: merging Rust + ${#TFLITE_LIBS[@]} TFLite archives for ${ABI}"

TMP_OUT="$(mktemp "${TMPDIR:-/tmp}/libdtln.XXXXXX")"
dtln_rs_merge_android_libdtln "${TMP_OUT}" "${RUST_LIB}" "${TFLITE_LIBS[@]}"
merged_size="$(ls -lh "${TMP_OUT}" | awk '{print $5}')"
echo "dtln-rs: merged libdtln.a ${merged_size} for ${ABI}"

dtln_rs_install_lib "${OUT}" "${TMP_OUT}"
rm -f "${TMP_OUT}"

# Legacy split layout (libdtln.a + deps/) — remove so repo only carries one .a per ABI.
if [[ -d "${DEPS_DIR}" ]]; then
  rm -rf "${DEPS_DIR}"
  echo "dtln-rs: removed legacy ${DEPS_DIR}"
fi
