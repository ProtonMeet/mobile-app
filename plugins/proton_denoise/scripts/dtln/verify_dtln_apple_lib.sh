#!/usr/bin/env bash
# Usage: verify_dtln_apple_lib.sh <iphoneos|iphonesimulator|macosx> <lib.a> [arch]
# Optional arch (e.g. arm64): verify only that slice of a fat archive.
# Exits 0 when every checked object matches the expected Apple platform.
# Supports thin and lipo fat static archives (macOS / iOS simulator universal libs).
set -euo pipefail

platform="${1:-}"
lib="${2:-}"
only_arch="${3:-}"

case "${platform}" in
  iphoneos) expected=2 ;;
  iphonesimulator) expected=7 ;;
  macosx) expected=1 ;;
  *)
    echo "verify_dtln_apple_lib: unsupported platform ${platform}" >&2
    exit 1
    ;;
esac

if [[ ! -f "${lib}" ]]; then
  echo "verify_dtln_apple_lib: missing ${lib}" >&2
  exit 1
fi

# libdtln_tflite.a is TFLite-only (no DTLN C FFI).
require_c_api=1
lib_base="$(basename "${lib}")"
if [[ "${lib_base}" == libdtln_tflite.a || "${lib_base}" == libdtln_tflite-*.a ]]; then
  require_c_api=0
fi

verify_ar_bin() {
  if command -v xcrun >/dev/null 2>&1; then
    xcrun --find llvm-ar 2>/dev/null || true
  fi
}

pick_verify_member() {
  local archive="$1"
  local archive_base member ar_bin

  archive_base="$(basename "${archive}")"
  ar_bin="$(verify_ar_bin)"
  ar_bin="${ar_bin:-ar}"
  if [[ "${archive_base}" == libdtln_tflite.a || "${archive_base}" == libdtln_tflite-*.a ]]; then
    if "${ar_bin}" -t "${archive}" 2>/dev/null | grep -F 'city.cc.o' >/dev/null 2>&1; then
      echo "city.cc.o"
      return 0
    fi
    member="$("${ar_bin}" -t "${archive}" 2>/dev/null | sed -n '1p' || true)"
    if [[ -n "${member}" ]]; then
      echo "${member}"
      return 0
    fi
  elif [[ "${archive_base}" == libdtln.a && "${platform}" != macosx ]]; then
    if "${ar_bin}" -t "${archive}" 2>/dev/null | grep -F 'city.cc.o' >/dev/null 2>&1; then
      echo "verify_dtln_apple_lib: ${archive} embeds TFLite — iOS libdtln.a must be Rust-only" >&2
      echo "verify_dtln_apple_lib: rebuild — ./plugins/proton_denoise/scripts/dtln/build-dtln-rs.sh ios" >&2
      return 1
    fi
    member="$("${ar_bin}" -t "${archive}" 2>/dev/null | grep -E 'dtln_rs.*\.rcgu\.o$' | head -1 || true)"
    if [[ -n "${member}" ]]; then
      echo "${member}"
      return 0
    fi
  elif [[ "${archive_base}" == libdtln.a && "${platform}" == macosx ]]; then
    if "${ar_bin}" -t "${archive}" 2>/dev/null | grep -F 'city.cc.o' >/dev/null 2>&1; then
      echo "city.cc.o"
      return 0
    fi
  fi
  member="$("${ar_bin}" -t "${archive}" 2>/dev/null | grep -E '\.o$' | sed -n '1p' || true)"
  if [[ -z "${member}" ]]; then
    member="$("${ar_bin}" -t "${archive}" 2>/dev/null | sed -n '1p' || true)"
  fi
  if [[ -z "${member}" ]]; then
    echo "verify_dtln_apple_lib: cannot verify ${archive}" >&2
    return 1
  fi
  echo "${member}"
}

verify_thin_archive_platform() {
  local archive="$1"
  local expected_platform="$2"
  local tmpdir member actual ar_bin

  tmpdir="$(mktemp -d)"
  member="$(pick_verify_member "${archive}")" || {
    rm -rf "${tmpdir}"
    return 1
  }
  if [[ -z "${member}" ]]; then
    rm -rf "${tmpdir}"
    echo "verify_dtln_apple_lib: cannot verify ${archive}" >&2
    return 1
  fi
  ar_bin="$(verify_ar_bin)"
  ar_bin="${ar_bin:-ar}"
  (
    cd "${tmpdir}"
    "${ar_bin}" -x "${archive}" "${member}"
  )
  actual="$(otool -l "${tmpdir}/${member}" 2>/dev/null | awk '/platform / {print $2; exit}')"
  if [[ -z "${actual}" ]]; then
    case "${expected_platform}" in
      2) actual="$(otool -arch arm64 -l "${tmpdir}/${member}" 2>/dev/null | awk '/platform / {print $2; exit}')" ;;
      7) actual="$(otool -arch arm64 -l "${tmpdir}/${member}" 2>/dev/null | awk '/platform / {print $2; exit}')" ;;
    esac
  fi
  rm -rf "${tmpdir}"
  if [[ -z "${actual}" || "${actual}" != "${expected_platform}" ]]; then
    echo "verify_dtln_apple_lib: ${archive} (${member}) platform ${actual:-unknown}, expected ${expected_platform}" >&2
    return 1
  fi
}

verify_archive_exports_c_api() {
  local archive="$1"
  local sym_file
  sym_file="$(mktemp)"
  # Avoid `nm | grep -q` under pipefail — grep -q closes the pipe and nm exits 141.
  nm "${archive}" 2>/dev/null >"${sym_file}" || true
  if grep -qE '[[:space:]]_dtln_create$' "${sym_file}"; then
    rm -f "${sym_file}"
    return 0
  fi
  rm -f "${sym_file}"
  echo "verify_dtln_apple_lib: ${archive} missing C API symbol _dtln_create" >&2
  case "${platform}" in
    macosx) echo "verify_dtln_apple_lib: rebuild — ./plugins/proton_denoise/scripts/dtln/build-dtln-rs.sh macos" >&2 ;;
    *) echo "verify_dtln_apple_lib: rebuild — ./plugins/proton_denoise/scripts/dtln/build-dtln-rs.sh ${platform}" >&2 ;;
  esac
  return 1
}

lipo_info="$(lipo -info "${lib}" 2>&1)" || {
  echo "verify_dtln_apple_lib: lipo cannot read ${lib}" >&2
  exit 1
}

if [[ "${lipo_info}" == *"Architectures in the fat file"* ]]; then
  thin_dir="$(mktemp -d)"
  archs="$(lipo -archs "${lib}")"
  if [[ -n "${only_arch}" ]]; then
    if ! grep -qw "${only_arch}" <<<"${archs}"; then
      rm -rf "${thin_dir}"
      echo "verify_dtln_apple_lib: ${lib} has no ${only_arch} slice (has: ${archs})" >&2
      exit 1
    fi
    archs="${only_arch}"
  fi
  for arch in ${archs}; do
    thin="${thin_dir}/${arch}.a"
    lipo -thin "${arch}" "${lib}" -output "${thin}"
    verify_thin_archive_platform "${thin}" "${expected}" || {
      rm -rf "${thin_dir}"
      exit 1
    }
    if [[ "${require_c_api}" -eq 1 ]]; then
      verify_archive_exports_c_api "${thin}" || {
        rm -rf "${thin_dir}"
        exit 1
      }
    fi
  done
  rm -rf "${thin_dir}"
else
  if [[ -n "${only_arch}" ]]; then
    echo "verify_dtln_apple_lib: ${lib} is not fat — cannot check ${only_arch} slice" >&2
    exit 1
  fi
  verify_thin_archive_platform "${lib}" "${expected}"
  if [[ "${require_c_api}" -eq 1 ]]; then
    verify_archive_exports_c_api "${lib}"
  fi
fi
