# proton_denoise

Cross-platform RNNoise noise suppression for Proton Meet, structured like [flutter-webrtc](https://github.com/flutter-webrtc/flutter-webrtc):

| Layer                             | Role                                                             |
| --------------------------------- | ---------------------------------------------------------------- |
| `third_party/rnnoise/include/`    | Public `rnnoise.h` (upstream API)                                |
| `cmake/` + `scripts/`             | **Compile-time** RNNoise build (FetchContent xiph/rnnoise v0.2)  |
| `common/cpp/`                     | Shared C++ processor + stable **C API** (`proton_denoise_api.h`) |
| `macos/`, `windows/`, `linux/`, … | Thin Flutter plugin glue (method channel)                        |
| `lib/`                            | Dart facade                                                      |

Your old flutter-webrtc patch embedded RNNoise inside the WebRTC plugin (`common/cpp` + `AudioRnnoiseProcessor` on Darwin). This plugin moves that stack **down** so:

- Desktop/mobile builds link one RNNoise implementation.
- `flutter-webrtc` (or LiveKit) can call the C API from native capture callbacks later, instead of forking the plugin.

## Layout

```
proton_denoise/
├── common/cpp/include/   # proton_denoise_api.h, processor
├── common/cpp/src/
├── third_party/rnnoise/include/rnnoise.h
├── cmake/rnnoise.cmake, rnnoise_upstream.cmake, shims/
├── scripts/build_rnnoise.sh, build_rnnoise_apple.sh
├── lib/proton_denoise.dart
└── macos|windows|linux|ios|android/
```

## RNNoise build (compile time)

RNNoise is **not** vendored as prebuilt `.a` / `.lib` files. On each native build:

1. [xiph/rnnoise](https://github.com/xiph/rnnoise) `v0.2` is fetched (CMake `FetchContent`).
2. Model weights are downloaded via upstream `download_model.sh` (needs `curl` or `wget`, once per cache).
3. A static `librnnoise` is built for the active OS/arch via `CMAKE_OSX_DEPLOYMENT_TARGET` (no manual `-mmacosx-version-min` on iOS).

**iOS / macOS:** CocoaPods runs `scripts/build_rnnoise_apple.sh` before compiling the pod. Requires **CMake 3.14+** on the build machine (`brew install cmake`). Xcode’s script phase uses a minimal `PATH`; the script searches Homebrew, `/Applications/CMake.app`, and `ANDROID_HOME/cmake/...`. Override with `RNNOISE_CMAKE=/path/to/cmake` if needed.

**Android:** Gradle `externalNativeBuild` (CMake) builds `libproton_denoise.so` with RNNoise via `cmake/rnnoise.cmake`; Kotlin JNI calls the same C API as Darwin.

There is no single “universal” `.so` on Android (unlike a macOS fat archive). AGP compiles **one shared library per ABI** (`armeabi-v7a`, `arm64-v8a`, `x86`, `x86_64`, …); the **host app’s** `ndk.abiFilters` (Meet: `armeabi-v7a`, `arm64-v8a`, `x86_64`) selects which slices are packaged into the APK/AAB. This plugin does not pin `abiFilters`, so it can supply every ABI the app requests. First CMake configure needs network for FetchContent + model download.

CMake/Ninja intermediates (`.cxx`, FetchContent `_deps`) go to **`build/native/proton_denoise/cxx`** at the Flutter project root (`buildStagingDirectory`), not under `plugins/proton_denoise/android/`.

**Linux / Windows:** `cmake/rnnoise.cmake` builds and links the `rnnoise` target into the Flutter plugin.

Manual test (macOS arm64):

```bash
TARGET_TEMP_DIR=/tmp/rnnoise-build MACOSX_DEPLOYMENT_TARGET=12.0 \
  PLATFORM_NAME=macosx ARCHS=arm64 CONFIGURATION=Debug \
  ./scripts/build_rnnoise.sh apple /tmp/rnnoise-build/librnnoise.a
```

First build needs network access for git + Xiph model tarball.

## App usage

```yaml
dependencies:
  proton_denoise:
    path: plugins/proton_denoise
```

```dart
import 'package:proton_denoise/proton_denoise.dart';

await ProtonDenoise.instance.initialize();
await ProtonDenoise.instance.setEnabled(true);
```

## flutter-webrtc integration (iOS / macOS)

flutter-webrtc attaches capture processors per local audio track via `LocalAudioTrack.addProcessing`.

This plugin registers `RnnoiseProcessor` on the track when you call:

```dart
await ProtonDenoise.instance.setCaptureDenoiseEnabled(true);
```

That applies RNNoise to **all local microphone capture** (LiveKit `LocalAudioTrack` / WebRTC mic tracks).

**Linux / Windows:** The plugin registers `me.proton.meet/denoise` (attach/detach/list types) and `proton_denoise` (RNNoise C API / `processFrame` for tests). RNNoise is built via `cmake/rnnoise.cmake`. WebRTC track attach uses the same `flutter_webrtc_plugin` shared-instance lookup as `proton_video_effects`; live mic post-processing on desktop still depends on flutter_webrtc exposing a capture hook (attach succeeds and enables the RNNoise handle).

## C API (for native consumers)

```c
ProtonDenoiseHandle* h = proton_denoise_create();
proton_denoise_set_enabled(h, 1);
proton_denoise_process_interleaved(h, pcm, sample_count, channels);
proton_denoise_destroy(h);
```

Headers live in `common/cpp/include/proton_denoise_api.h`.
