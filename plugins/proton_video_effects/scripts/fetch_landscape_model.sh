#!/usr/bin/env bash
# Download MediaPipe landscape selfie segmenter (Google Meet variant, 144×256).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
URL="https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_segmenter_landscape/float16/latest/selfie_segmenter_landscape.tflite"
DEST_ANDROID="$ROOT/android/src/main/assets/selfie_segmenter_landscape.tflite"
DEST_IOS="$ROOT/ios/Resources/selfie_segmenter_landscape.tflite"
curl -fsSL -o "$DEST_ANDROID" "$URL"
cp "$DEST_ANDROID" "$DEST_IOS"
ls -la "$DEST_ANDROID" "$DEST_IOS"
