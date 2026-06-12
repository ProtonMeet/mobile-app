#!/usr/bin/env bash
# Wrap macOS libdeepfilter.dylib (fat or per-arch) as DeepFilter.framework for CocoaPods.
set -euo pipefail

plugin_root="$(cd "$(dirname "$0")/../.." && pwd)"
repo_root="$(cd "${plugin_root}/../.." && pwd)"
df_root="${plugin_root}/third_party/deepfilter"
apple_staging="${DEEPFILTER_STAGING_DIR:-${repo_root}/.local/deepfilter-staging}/apple/macos"
header="${df_root}/include/deep_filter.h"
framework="${df_root}/macos/DeepFilter.framework"

fat_dylib="${apple_staging}/libdeepfilter.dylib"
arm64_dylib="${apple_staging}/arm64/libdeepfilter.dylib"
x86_dylib="${apple_staging}/x86_64/libdeepfilter.dylib"

resolve_dylib() {
  if [[ -f "${fat_dylib}" ]]; then
    echo "${fat_dylib}"
    return 0
  fi
  if [[ -f "${arm64_dylib}" && -f "${x86_dylib}" ]]; then
    local tmp
    tmp="$(mktemp -t libdeepfilter-fat).dylib"
    lipo -create "${arm64_dylib}" "${x86_dylib}" -output "${tmp}"
    echo "${tmp}"
    return 0
  fi
  if [[ -f "${arm64_dylib}" ]]; then
    echo "${arm64_dylib}"
    return 0
  fi
  echo "package_deepfilter_macos_framework: missing ${fat_dylib}" >&2
  echo "package_deepfilter_macos_framework: run ./plugins/proton_denoise/scripts/deepfilter/build-deepfilter.sh macos" >&2
  return 1
}

src_dylib="$(resolve_dylib)"
cleanup_tmp=
if [[ "${src_dylib}" != "${fat_dylib}" && "${src_dylib}" != "${arm64_dylib}" ]]; then
  cleanup_tmp="${src_dylib}"
fi

version_dir="${framework}/Versions/A"
rm -rf "${framework}"
mkdir -p "${version_dir}/Headers" "${version_dir}/Modules" "${version_dir}/Resources"
cp -f "${src_dylib}" "${version_dir}/DeepFilter"
[[ -n "${cleanup_tmp}" ]] && rm -f "${cleanup_tmp}"

if command -v install_name_tool >/dev/null 2>&1; then
  install_name="@rpath/DeepFilter.framework/Versions/A/DeepFilter"
  old_id="$(otool -D "${version_dir}/DeepFilter" 2>/dev/null | awk 'NF && $1 !~ /:/ {print; exit}')"
  install_name_tool -id "${install_name}" "${version_dir}/DeepFilter"
  if [[ -n "${old_id:-}" && "${old_id}" != "${install_name}" ]]; then
    install_name_tool -change "${old_id}" "${install_name}" "${version_dir}/DeepFilter" 2>/dev/null || true
  fi
fi

cp -f "${header}" "${version_dir}/Headers/deep_filter.h"

cat >"${version_dir}/Modules/module.modulemap" <<'EOF'
framework module DeepFilter {
  header "deep_filter.h"
  export *
}
EOF

cat >"${version_dir}/Resources/Info.plist" <<'EOF'
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
</dict>
</plist>
EOF

(
  cd "${framework}/Versions"
  ln -sfh A Current
)
(
  cd "${framework}"
  ln -sfh Versions/Current/DeepFilter DeepFilter
  ln -sfh Versions/Current/Headers Headers
  ln -sfh Versions/Current/Modules Modules
  ln -sfh Versions/Current/Resources Resources
)

if command -v lipo >/dev/null 2>&1; then
  lipo -info "${version_dir}/DeepFilter"
fi
echo "package_deepfilter_macos_framework: created ${framework}"
