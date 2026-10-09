#!/usr/bin/env bash
# Keep native flutter_webrtc references aligned with the resolved pub version.
#
# After bumping livekit_client / flutter_webrtc in pubspec.yaml:
#   flutter pub get
#   sh scripts/sync_flutter_webrtc_native_refs.sh
#
# Updates:
#   - plugins/*/ios|macos/*/Package.swift  (SPM path ../flutter_webrtc-<version>)
#   - android/gradle/libs.versions.toml    (webrtc-sdk + comment)
#   - plugins/*/android/build.gradle.kts   (compileOnly webrtc-sdk AAR)
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
cd "$ROOT"

LOCK="$ROOT/pubspec.lock"
if [[ ! -f "$LOCK" ]]; then
  echo "sync_flutter_webrtc_native_refs: missing pubspec.lock — run flutter pub get first" >&2
  exit 1
fi

VERSION=$(
  awk '
    /^  flutter_webrtc:$/ { found=1; next }
    found && /^    version: "/ {
      gsub(/"/, "", $2)
      print $2
      exit
    }
  ' "$LOCK"
)

if [[ -z "$VERSION" ]]; then
  echo "sync_flutter_webrtc_native_refs: could not read flutter_webrtc version from pubspec.lock" >&2
  exit 1
fi

PUB_CACHE="${PUB_CACHE:-$HOME/.pub-cache}"
PKG_DIR="$PUB_CACHE/hosted/pub.dev/flutter_webrtc-$VERSION"
GRADLE="$PKG_DIR/android/build.gradle"
if [[ ! -f "$GRADLE" ]]; then
  echo "sync_flutter_webrtc_native_refs: package not in pub-cache: $GRADLE" >&2
  echo "  Run: flutter pub get" >&2
  exit 1
fi

WEBRTC_SDK=$(
  grep -Eo "io\.github\.webrtc-sdk:android:[0-9.]+" "$GRADLE" | head -1 | cut -d: -f3
)
if [[ -z "$WEBRTC_SDK" ]]; then
  echo "sync_flutter_webrtc_native_refs: could not parse webrtc-sdk from $GRADLE" >&2
  exit 1
fi

echo "sync_flutter_webrtc_native_refs: flutter_webrtc $VERSION, webrtc-sdk android $WEBRTC_SDK"

PACKAGE_SWIFTS=(
  plugins/proton_denoise/ios/proton_denoise/Package.swift
  plugins/proton_denoise/macos/proton_denoise/Package.swift
  plugins/proton_video_effects/ios/proton_video_effects/Package.swift
  plugins/proton_video_effects/macos/proton_video_effects/Package.swift
)

for f in "${PACKAGE_SWIFTS[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "sync_flutter_webrtc_native_refs: missing $f" >&2
    exit 1
  fi
  perl -pi -e 's|path: "\.\./flutter_webrtc-[^"]+"|path: "../flutter_webrtc-'"$VERSION"'"|g' "$f"
done

TOML="$ROOT/android/gradle/libs.versions.toml"
perl -pi -e 's|^webrtc-sdk = "[^"]+"|webrtc-sdk = "'"$WEBRTC_SDK"'"|' "$TOML"
# Comment documents both the Maven coordinate and the pub package — update both or they drift.
perl -pi -e 's|`io\.github\.webrtc-sdk:android:[0-9.]+`|`io.github.webrtc-sdk:android:'"$WEBRTC_SDK"'`|g' "$TOML"
perl -pi -e 's|as of flutter_webrtc [^)]+|as of flutter_webrtc '"$VERSION"'|' "$TOML"

GRADLE_KTS=(
  plugins/proton_denoise/android/build.gradle.kts
  plugins/proton_video_effects/android/build.gradle.kts
)
for f in "${GRADLE_KTS[@]}"; do
  perl -pi -e 's|compileOnly\("io\.github\.webrtc-sdk:android:[^"]+"\)|compileOnly("io.github.webrtc-sdk:android:'"$WEBRTC_SDK"'")|g' "$f"
done

echo "sync_flutter_webrtc_native_refs: done"
