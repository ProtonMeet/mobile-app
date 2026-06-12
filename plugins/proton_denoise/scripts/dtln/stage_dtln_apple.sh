#!/usr/bin/env bash
# Copies the correct prebuilt libdtln.a slice into BUILT_PRODUCTS_DIR for linking.
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
plugin_root="$(cd "${script_dir}/../.." && pwd)"
dtln_root="${plugin_root}/third_party/dtln-rs/lib"
verify_script="${script_dir}/verify_dtln_apple_lib.sh"
out="${BUILT_PRODUCTS_DIR}/libdtln.a"

case "${PLATFORM_NAME:-}" in
  iphoneos)
    src="${dtln_root}/ios/device/libdtln.a"
    ;;
  iphonesimulator)
    src="${dtln_root}/ios/simulator/libdtln.a"
    ;;
  macosx)
    src="${dtln_root}/macos/libdtln.a"
    ;;
  *)
    echo "stage_dtln_apple: unsupported PLATFORM_NAME=${PLATFORM_NAME:-}" >&2
    exit 1
    ;;
esac

stage_tflite=1
if [[ "${PLATFORM_NAME:-}" == macosx ]]; then
  stage_tflite=0
fi

if [[ ! -f "${src}" ]]; then
  echo "stage_dtln_apple: missing ${src} — run plugins/proton_denoise/scripts/dtln/build-dtln-rs.sh apple" >&2
  exit 1
fi

# Xcode links one simulator arch at a time. Fat prebuilts may carry a stale slice for
# the other sim arch; thin to the arch we are building before verify/stage.
dtln_resolve_slice_arch() {
  if [[ -n "${CURRENT_ARCH:-}" && "${CURRENT_ARCH}" != "undefined_arch" ]]; then
    echo "${CURRENT_ARCH}"
    return 0
  fi
  case "$(uname -m)" in
    arm64) echo "arm64" ;;
    x86_64) echo "x86_64" ;;
    *)
      echo "stage_dtln_apple: unsupported build host $(uname -m)" >&2
      return 1
      ;;
  esac
}

dtln_materialize_archive_slice() {
  local src_archive="$1"
  local dest_archive="$2"
  local slice_arch="$3"
  local lipo_info

  lipo_info="$(lipo -info "${src_archive}" 2>&1)" || {
    echo "stage_dtln_apple: lipo cannot read ${src_archive}" >&2
    return 1
  }
  if [[ "${lipo_info}" != *"Architectures in the fat file"* ]]; then
    cp -f "${src_archive}" "${dest_archive}"
    return 0
  fi
  if ! lipo -info "${src_archive}" 2>&1 | grep -qw "${slice_arch}"; then
    echo "stage_dtln_apple: ${src_archive} missing ${slice_arch} slice" >&2
    echo "stage_dtln_apple: rebuild iOS libs — ./plugins/proton_denoise/scripts/dtln/build-dtln-rs.sh ios" >&2
    return 1
  fi
  lipo -thin "${slice_arch}" "${src_archive}" -output "${dest_archive}"
}

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/stage-dtln.XXXXXX")"
cleanup() {
  rm -rf "${work_dir}"
}
trap cleanup EXIT

verify_src="${src}"
if [[ "${PLATFORM_NAME:-}" == iphonesimulator ]]; then
  slice_arch="$(dtln_resolve_slice_arch)"
  verify_src="${work_dir}/libdtln-${slice_arch}.a"
  dtln_materialize_archive_slice "${src}" "${verify_src}" "${slice_arch}"
fi

if ! sh "${verify_script}" "${PLATFORM_NAME}" "${verify_src}"; then
  echo "stage_dtln_apple: cannot verify ${verify_src} (from ${src})" >&2
  case "${PLATFORM_NAME}" in
    macosx)
      echo "stage_dtln_apple: rebuild macOS lib — ./plugins/proton_denoise/scripts/dtln/build-dtln-rs.sh macos" >&2
      ;;
    *)
      echo "stage_dtln_apple: rebuild iOS libs — ./plugins/proton_denoise/scripts/dtln/build-dtln-rs.sh ios" >&2
      ;;
  esac
  exit 1
fi

# Xcode may skip this script when ${out} exists; drop stale archives (e.g. pre-FFI libdtln.a).
if [[ -f "${out}" ]] && ! sh "${verify_script}" "${PLATFORM_NAME}" "${out}"; then
  echo "stage_dtln_apple: removing invalid staged ${out}" >&2
  rm -f "${out}"
fi

if [[ -f "${out}" ]] && cmp -s "${verify_src}" "${out}"; then
  echo "stage_dtln_apple: ${out} is up to date"
else
  mkdir -p "$(dirname "${out}")"
  cp -f "${verify_src}" "${out}"
  echo "stage_dtln_apple: staged ${out} from ${src}"
fi

tflite_src="$(dirname "${src}")/libdtln_tflite.a"
tflite_out="${BUILT_PRODUCTS_DIR}/libdtln_tflite.a"
if [[ "${stage_tflite}" -eq 1 ]]; then
  if [[ ! -f "${tflite_src}" ]]; then
    echo "stage_dtln_apple: missing ${tflite_src}" >&2
    echo "stage_dtln_apple: rebuild iOS libs — ./plugins/proton_denoise/scripts/dtln/build-dtln-rs.sh ios" >&2
    exit 1
  fi
  verify_tflite="${tflite_src}"
  if [[ "${PLATFORM_NAME:-}" == iphonesimulator ]]; then
    slice_arch="$(dtln_resolve_slice_arch)"
    verify_tflite="${work_dir}/libdtln_tflite-${slice_arch}.a"
    dtln_materialize_archive_slice "${tflite_src}" "${verify_tflite}" "${slice_arch}"
  fi
  if ! sh "${verify_script}" "${PLATFORM_NAME}" "${verify_tflite}"; then
    echo "stage_dtln_apple: cannot verify ${verify_tflite} (from ${tflite_src})" >&2
    echo "stage_dtln_apple: rebuild iOS libs — ./plugins/proton_denoise/scripts/dtln/build-dtln-rs.sh ios" >&2
    exit 1
  fi
  if [[ -f "${tflite_out}" ]] && ! sh "${verify_script}" "${PLATFORM_NAME}" "${tflite_out}"; then
    echo "stage_dtln_apple: removing invalid staged ${tflite_out}" >&2
    rm -f "${tflite_out}"
  fi
  if [[ -f "${tflite_out}" ]] && cmp -s "${verify_tflite}" "${tflite_out}"; then
    echo "stage_dtln_apple: ${tflite_out} is up to date"
  else
    mkdir -p "$(dirname "${tflite_out}")"
    cp -f "${verify_tflite}" "${tflite_out}"
    echo "stage_dtln_apple: staged ${tflite_out} from ${tflite_src}"
  fi
fi
