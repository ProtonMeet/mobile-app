# Desktop native core (TensorFlow Lite)

Linux and Windows use this C++ library (same `.tflite` models as Android/iOS).

## Build TensorFlow Lite

From a TensorFlow source tree (tag `v2.17.0` matches Android Maven):

```bash
git clone --depth 1 --branch v2.17.0 https://github.com/tensorflow/tensorflow.git
cmake -S tensorflow/tensorflow/lite -B tflite-build \
  -DCMAKE_BUILD_TYPE=Release \
  -DTFLITE_ENABLE_XNNPACK=ON \
  -DTFLITE_ENABLE_GPU=OFF
cmake --build tflite-build -j
```

Or run the helper script from the plugin root:

```bash
./scripts/build_tflite_desktop.sh
```

## Configure the Flutter plugin

When building Meet for Linux/Windows, pass the CMake build directory:

```bash
flutter build linux --dart-define=appEnv=prod \
  --cmake-args="-DTFLITE_ROOT=/absolute/path/to/tflite-build"
```

Without `TFLITE_ROOT`, the plugin compiles but `isBackgroundBlurReady` returns `false`.

## Models

`selfie_segmenter.tflite` is copied from `android/src/main/assets/` next to
`libproton_video_effects_plugin.so` / `proton_video_effects_plugin.dll` at build time.

## Frame pipeline (flutter_webrtc)

`attach` / `detach` use the same method channel as mobile. End-to-end blur on the
**published** camera track still needs a desktop `VideoProcessingAdapter` in
`flutter_webrtc` (iOS/Android already have this). The native engine here is ready
for that hook via `meet_video_effects_process_i420()`.
