#!/usr/bin/env bash
# Shared PATH / Rust / Apple cross-compile helpers for proton_denoise native builds.
# Sourced by scripts/dtln/build-dtln-rs-env.sh and scripts/deepfilter/build-deepfilter-env.sh.
set -euo pipefail

native_repo_root() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "${script_dir}/../../.." && pwd
}

# Match ios/Flutter/AppFrameworkInfo.plist / Podfile platform (Runner app minimum).
native_main_app_ios_deployment_target() {
  local repo_root="${1:-$(native_repo_root)}"
  local version=""
  local app_plist="${repo_root}/ios/Flutter/AppFrameworkInfo.plist"
  local podfile="${repo_root}/ios/Podfile"

  if [[ -f "${app_plist}" ]]; then
    version="$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "${app_plist}" 2>/dev/null || true)"
  fi
  if [[ -z "${version}" && -f "${podfile}" ]]; then
    version="$(grep -E "^platform :ios, " "${podfile}" | sed -E "s/platform :ios, ['\"]([^'\"]+)['\"].*/\1/" | head -1)"
  fi
  if [[ -z "${version}" ]]; then
    echo "native build: could not resolve main app iOS deployment target" >&2
    version="16.0"
  fi
  echo "${version}"
}

native_prepend_path() {
  local dir ndk_cmake
  for dir in \
    /opt/homebrew/bin \
    /usr/local/bin \
    /Applications/CMake.app/Contents/bin \
    "${HOME}/.cargo/bin" \
    "${HOME}/.local/bin" \
    "${HOME}/bin"
  do
    if [[ -d "${dir}" ]]; then
      PATH="${dir}:${PATH}"
    fi
  done

  if [[ -n "${ANDROID_HOME:-}" ]]; then
    ndk_cmake="$(ls -d "${ANDROID_HOME}/cmake/"*/bin 2>/dev/null | sort -V | tail -n 1 || true)"
    if [[ -n "${ndk_cmake}" && -d "${ndk_cmake}" ]]; then
      PATH="${ndk_cmake}:${PATH}"
    fi
  fi
  export PATH
}

native_require_cmd() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    echo "native build: required command not found: ${name}" >&2
    exit 1
  fi
}

native_resolve_rust() {
  native_prepend_path
  native_require_cmd cargo
  native_require_cmd rustc
}

# Rust triple → Cargo env suffix (aarch64-apple-ios-sim → aarch64_apple_ios_sim).
native_triple_to_cargo_env() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr '-' '_'
}

# Configure cc/cxx for Apple cross-builds. Optional extra_rustflags appended per triple.
native_export_apple_cc_env() {
  local triple="$1"
  local extra_rustflags="${2:-}"
  local cc_key cargo_target_key rustflags_var
  cc_key="$(native_triple_to_cargo_env "${triple}")"
  cargo_target_key="$(echo "${triple}" | tr '[:lower:]' '[:upper:]' | tr '-' '_')"
  rustflags_var="CARGO_TARGET_${cargo_target_key}_RUSTFLAGS"

  unset ARCH ARCHS CURRENT_ARCH PLATFORM_NAME EFFECTIVE_PLATFORM_NAME 2>/dev/null || true
  export CRATE_CC_NO_DEFAULTS=1

  case "${triple}" in
    aarch64-apple-ios)
      native_require_cmd xcrun
      export IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-15.0}"
      local ios_sdk ios_clang ios_cflags
      ios_sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
      ios_clang="$(xcrun --sdk iphoneos --find clang)"
      ios_cflags="-target arm64-apple-ios${IPHONEOS_DEPLOYMENT_TARGET} -isysroot ${ios_sdk} -miphoneos-version-min=${IPHONEOS_DEPLOYMENT_TARGET}"
      export "CC_${cc_key}=${ios_clang}"
      export "CXX_${cc_key}=${ios_clang}++"
      export "CFLAGS_${cc_key}=${ios_cflags}"
      export "CXXFLAGS_${cc_key}=${ios_cflags}"
      export "${rustflags_var}=-C link-arg=-miphoneos-version-min=${IPHONEOS_DEPLOYMENT_TARGET}"
      ;;
    aarch64-apple-ios-sim)
      native_require_cmd xcrun
      export IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-15.0}"
      local sim_sdk sim_clang sim_cflags
      sim_sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
      sim_clang="$(xcrun --sdk iphonesimulator --find clang)"
      sim_cflags="-target arm64-apple-ios${IPHONEOS_DEPLOYMENT_TARGET}-simulator -isysroot ${sim_sdk} -mios-simulator-version-min=${IPHONEOS_DEPLOYMENT_TARGET}"
      export "CC_${cc_key}=${sim_clang}"
      export "CXX_${cc_key}=${sim_clang}++"
      export "CFLAGS_${cc_key}=${sim_cflags}"
      export "CXXFLAGS_${cc_key}=${sim_cflags}"
      export "${rustflags_var}=-C link-arg=-mios-simulator-version-min=${IPHONEOS_DEPLOYMENT_TARGET}"
      ;;
    x86_64-apple-ios)
      native_require_cmd xcrun
      export IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-15.0}"
      local xsim_sdk xsim_clang xsim_cflags
      xsim_sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
      xsim_clang="$(xcrun --sdk iphonesimulator --find clang)"
      xsim_cflags="-target x86_64-apple-ios${IPHONEOS_DEPLOYMENT_TARGET}-simulator -isysroot ${xsim_sdk} -mios-simulator-version-min=${IPHONEOS_DEPLOYMENT_TARGET}"
      export "CC_${cc_key}=${xsim_clang}"
      export "CXX_${cc_key}=${xsim_clang}++"
      export "CFLAGS_${cc_key}=${xsim_cflags}"
      export "CXXFLAGS_${cc_key}=${xsim_cflags}"
      export "${rustflags_var}=-C link-arg=-mios-simulator-version-min=${IPHONEOS_DEPLOYMENT_TARGET}"
      ;;
    aarch64-apple-darwin | x86_64-apple-darwin)
      native_require_cmd xcrun
      export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-12.0}"
      local mac_sdk mac_clang mac_cflags
      mac_sdk="$(xcrun --sdk macosx --show-sdk-path)"
      mac_clang="$(xcrun --sdk macosx --find clang)"
      mac_cflags="-target ${triple} -isysroot ${mac_sdk} -mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET}"
      export "CC_${cc_key}=${mac_clang}"
      export "CXX_${cc_key}=${mac_clang}++"
      export "CFLAGS_${cc_key}=${mac_cflags}"
      export "CXXFLAGS_${cc_key}=${mac_cflags}"
      export "${rustflags_var}=-C link-arg=-mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET}"
      ;;
    *)
      echo "native build: unsupported Apple triple ${triple}" >&2
      return 1
      ;;
  esac

  if [[ -n "${extra_rustflags}" ]]; then
    local existing="${!rustflags_var:-}"
    if [[ -n "${existing}" ]]; then
      export "${rustflags_var}=${existing} ${extra_rustflags}"
    else
      export "${rustflags_var}=${extra_rustflags}"
    fi
  fi

  # Global CC/CXX for post-cargo steps (static lib merge, lipo staging).
  local cc_var="CC_${cc_key}" cxx_var="CXX_${cc_key}"
  local cflags_var="CFLAGS_${cc_key}" cxxflags_var="CXXFLAGS_${cc_key}"
  if [[ -n "${!cc_var:-}" ]]; then
    export CC="${!cc_var}"
    export CXX="${!cxx_var}"
    export CFLAGS="${!cflags_var}"
    export CXXFLAGS="${!cxxflags_var}"
  fi
}
