#!/usr/bin/env bash
#
# Builds the TensorFlow Lite C shared library for Linux x64 and stages it into
# native/third_party/tflite.
#
# The result of this script is committed to the repository, so a normal
# `flutter build linux` needs nothing from here. Run it only to refresh the
# vendored binary, to move to a new TensorFlow release, or to verify the
# committed artifacts are reproducible.
#
# Steps: shallow-clone the pinned TensorFlow tag, apply tflite-<ref>-proton.patch,
# build tensorflow/lite/c, then stage the headers and library. See ../README.md
# for what each patch hunk is for.
#
# Requires: git, cmake (3.16+), ninja, a C++20-capable GCC or Clang.
#
# Usage:
#   ./build_tflite.sh
#   REF=v2.17.0 WORK_DIR=/var/tmp/tflite ./build_tflite.sh
#   NO_STAGE=1 ./build_tflite.sh          # build only, leave the vendor dir alone

set -euo pipefail

# TensorFlow git tag to build. A matching tflite-<ref>-proton.patch must exist
# next to this script; patches are not portable across releases.
REF="${REF:-v2.17.0}"
# Scratch directory for the clone and build tree; several GB, so kept out of the
# repo by default.
WORK_DIR="${WORK_DIR:-${TMPDIR:-/tmp}/proton-tflite-build}"
NO_STAGE="${NO_STAGE:-}"

ABI="linux-x64"
TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENDOR_DIR="$(dirname "$TOOLS_DIR")/third_party/tflite"
PATCH_FILE="$TOOLS_DIR/tflite-$REF-proton.patch"
SOURCE_DIR="$WORK_DIR/tensorflow_src"
BUILD_DIR="$WORK_DIR/build-c"

step() { printf '\033[36m==> %s\033[0m\n' "$1"; }
die() { printf '\033[31merror: %s\033[0m\n' "$1" >&2; exit 1; }

for tool in git cmake ninja; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is required but was not found on PATH."
done
[ -f "$PATCH_FILE" ] || die "No patch for $REF at $PATCH_FILE. Building a different TensorFlow release needs its own patch."

mkdir -p "$WORK_DIR"

if [ -d "$SOURCE_DIR/.git" ]; then
  step "Reusing TensorFlow clone at $SOURCE_DIR"
else
  step "Cloning TensorFlow $REF (shallow)"
  git clone --depth 1 --branch "$REF" https://github.com/tensorflow/tensorflow.git "$SOURCE_DIR"
fi

step "Applying $(basename "$PATCH_FILE")"
# --reverse --check succeeds only when the patch is already in the tree, which
# makes re-running this script safe.
if git -C "$SOURCE_DIR" apply --reverse --check "$PATCH_FILE" 2>/dev/null; then
  echo "    already applied, skipping"
else
  git -C "$SOURCE_DIR" apply --verbose "$PATCH_FILE"
fi

# Building tensorflow/lite/c (rather than tensorflow/lite) yields the
# self-contained tensorflowlite_c library; the plugin links the C API only.
# TFLITE_C_BUILD_SHARED_LIBS defaults to ON there and is set explicitly so the
# intent survives a CMake default change.
step "Configuring (Release, Ninja)"
cmake -G Ninja \
  -S "$SOURCE_DIR/tensorflow/lite/c" \
  -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DTFLITE_C_BUILD_SHARED_LIBS=ON

step "Building tensorflowlite_c (this takes a while)"
cmake --build "$BUILD_DIR"

SO="$BUILD_DIR/libtensorflowlite_c.so"
[ -f "$SO" ] || die "Expected build output missing: $SO"

if [ -n "$NO_STAGE" ]; then
  step "Build complete; staging skipped. Artifacts in $BUILD_DIR"
  exit 0
fi

step "Staging into third_party/tflite"
INC_DIR="$VENDOR_DIR/include"
LIB_DIR="$VENDOR_DIR/lib/$ABI"
rm -rf "$INC_DIR"
mkdir -p "$INC_DIR" "$LIB_DIR"

# Only the C API surface and what it includes transitively; the full tree is
# ~4000 headers and the plugin compiles against none of the C++ API.
#
# include/ is shared by every platform, which is safe because the same tag and
# patch produce the same headers no matter which platform stages them.
staged=0
for rel in tensorflow/lite/c tensorflow/lite/core tensorflow/lite/core/c tensorflow/lite/core/async/c; do
  mkdir -p "$INC_DIR/$rel"
  for header in "$SOURCE_DIR/$rel"/*.h; do
    [ -e "$header" ] || continue
    cp -f "$header" "$INC_DIR/$rel/"
    staged=$((staged + 1))
  done
done
# builtin_ops.h is the one header needed from tensorflow/lite itself.
mkdir -p "$INC_DIR/tensorflow/lite"
cp -f "$SOURCE_DIR/tensorflow/lite/builtin_ops.h" "$INC_DIR/tensorflow/lite/"
staged=$((staged + 1))
echo "    $staged headers -> $INC_DIR"

cp -f "$SO" "$LIB_DIR/"
# Apache-2.0 requires the licence to travel with the redistributed binary.
cp -f "$SOURCE_DIR/LICENSE" "$VENDOR_DIR/LICENSE"

echo
step "Done"
echo "    libtensorflowlite_c.so -> $LIB_DIR"
echo "    Update the version table in native/README.md if $REF changed, then commit."
