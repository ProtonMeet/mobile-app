#!/usr/bin/env bash
# Package libdeepfilter.dylib slices as DeepFilter.xcframework (iOS).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../native_build_env.sh
source "${SCRIPT_DIR}/../native_build_env.sh"

plugin_root="$(cd "${SCRIPT_DIR}/../.." && pwd)"
repo_root="$(native_repo_root)"
df_root="${plugin_root}/third_party/deepfilter"
apple_staging="${DEEPFILTER_STAGING_DIR:-${repo_root}/.local/deepfilter-staging}/apple/ios"
header="${df_root}/include/deep_filter.h"
xcframework="${df_root}/ios/DeepFilter.xcframework"
min_ios="${DEEPFILTER_MIN_IOS:-$(native_main_app_ios_deployment_target "${repo_root}")}"
build_staging="$(mktemp -d)"
trap 'rm -rf "${build_staging}"' EXIT

device_dylib="${apple_staging}/device-arm64/libdeepfilter.dylib"
sim_arm64_dylib="${apple_staging}/simulator-arm64/libdeepfilter.dylib"
sim_x86_dylib="${apple_staging}/simulator-x86_64/libdeepfilter.dylib"

if [[ ! -f "${device_dylib}" ]]; then
  echo "package_deepfilter_framework: missing ${device_dylib}" >&2
  echo "package_deepfilter_framework: run ./plugins/proton_denoise/scripts/deepfilter/build-deepfilter.sh ios (and ios-sim)" >&2
  exit 1
fi

write_framework() {
  local dylib="$1"
  local fw_dir="$2"
  rm -rf "${fw_dir}"
  mkdir -p "${fw_dir}/Headers" "${fw_dir}/Modules"
  cp -f "${dylib}" "${fw_dir}/DeepFilter"
  if command -v install_name_tool >/dev/null 2>&1; then
    install_name="@rpath/DeepFilter.framework/DeepFilter"
    old_id="$(otool -D "${fw_dir}/DeepFilter" 2>/dev/null | awk 'NF && $1 !~ /:/ {print; exit}')"
    install_name_tool -id "${install_name}" "${fw_dir}/DeepFilter"
    if [[ -n "${old_id:-}" && "${old_id}" != "${install_name}" ]]; then
      install_name_tool -change "${old_id}" "${install_name}" "${fw_dir}/DeepFilter" 2>/dev/null || true
    fi
  fi
  cp -f "${header}" "${fw_dir}/Headers/deep_filter.h"
  cat >"${fw_dir}/Modules/module.modulemap" <<'EOF'
framework module DeepFilter {
  header "deep_filter.h"
  export *
}
EOF
  cat >"${fw_dir}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>DeepFilter</string>
  <key>CFBundleIdentifier</key>
  <string>me.proton.meet.deepfilter</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>DeepFilter</string>
  <key>CFBundlePackageType</key>
  <string>FMWK</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>MinimumOSVersion</key>
  <string>${min_ios}</string>
</dict>
</plist>
EOF
}

device_fw="${build_staging}/device/DeepFilter.framework"
write_framework "${device_dylib}" "${device_fw}"

xc_args=(-create-xcframework -framework "${device_fw}")

if [[ -f "${sim_arm64_dylib}" && -f "${sim_x86_dylib}" ]]; then
  sim_fw="${build_staging}/simulator/DeepFilter.framework"
  write_framework "${sim_arm64_dylib}" "${sim_fw}"
  lipo -create "${sim_arm64_dylib}" "${sim_x86_dylib}" -output "${sim_fw}/DeepFilter"
  xc_args+=(-framework "${sim_fw}")
elif [[ -f "${sim_arm64_dylib}" ]]; then
  sim_fw="${build_staging}/simulator/DeepFilter.framework"
  write_framework "${sim_arm64_dylib}" "${sim_fw}"
  xc_args+=(-framework "${sim_fw}")
elif [[ -f "${sim_x86_dylib}" ]]; then
  sim_fw="${build_staging}/simulator/DeepFilter.framework"
  write_framework "${sim_x86_dylib}" "${sim_fw}"
  xc_args+=(-framework "${sim_fw}")
else
  echo "package_deepfilter_framework: no simulator slice — device-only xcframework" >&2
fi

mkdir -p "${df_root}/ios"
rm -rf "${xcframework}"
xcodebuild "${xc_args[@]}" -output "${xcframework}"

while IFS= read -r plist; do
  /usr/libexec/PlistBuddy -c "Set :MinimumOSVersion ${min_ios}" "${plist}" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :MinimumOSVersion string ${min_ios}" "${plist}"
  echo "package_deepfilter_framework: set MinimumOSVersion=${min_ios} in ${plist}"
done < <(find "${xcframework}" -path '*/DeepFilter.framework/Info.plist')

echo "package_deepfilter_framework: created ${xcframework}"
