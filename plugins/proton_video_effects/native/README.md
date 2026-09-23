# Desktop native core (TensorFlow Lite)

Linux and Windows use this C++ library (same `.tflite` models as Android/iOS).

## TensorFlow Lite runtime

**Nothing to install or configure.** A prebuilt TFLite C runtime is committed to
the repository under [`third_party/tflite/`](third_party/tflite/README.md) and
`CMakeLists.txt` finds it automatically, so a plain `flutter build windows` works
on a fresh clone. That directory documents the exact version, commit and build
configuration of the committed binaries.

Libraries live in per-ABI directories (`lib/windows-x64`, `lib/linux-x64`) and
only the directory matching the target being built is ever used. `lib/linux-x64`
is **not populated yet** — the `.so` must be built on Linux, and until it is
committed, Linux builds run with blur disabled.

To build against your own TFLite instead, set `TFLITE_ROOT` to a build tree or a
staged dist; it overrides the vendored copy. The Flutter CLI forwards no user
CMake arguments to desktop builds, so for `flutter build` it has to be an
environment variable:

```powershell
$env:TFLITE_ROOT = "C:\path\to\tflite-build"   # Windows
fvm flutter build windows
```
```bash
export TFLITE_ROOT=/path/to/tflite-build        # Linux
flutter build linux --dart-define=appEnv=prod
```

Driving CMake directly also accepts `-DTFLITE_ROOT=...`, which takes precedence
over the environment.

Either way, confirm it was picked up by looking for
`meet_video_effects: TFLite enabled (...)` in the build output — plus
`using vendored TFLite prebuilt (<abi>)` when the committed copy was used. If no
runtime is found the plugin still compiles, but the engine is never created, so
`isBackgroundBlurReady` returns `false` and blur and virtual backgrounds are both
inert. CMake warns in that case rather than failing.

## Rebuilding the runtime from source

Use the scripts in [`tools/`](tools); they clone the pinned tag, apply the patch,
build, and stage the result into `third_party/tflite/`:

```powershell
tools\build_tflite.ps1      # Windows: needs git, cmake, ninja, VS 2019+ C++ toolchain
```
```bash
tools/build_tflite.sh       # Linux: needs git, cmake 3.16+, ninja, C++20 GCC/Clang
```

The rest of this section is background: why this has to be built at all, and
what the accompanying patch does.

There is **no official prebuilt TFLite C library** for desktop. Upstream
(`tensorflow/tensorflow` and `google-ai-edge/litert`) both tell you to build it,
and `tensorflow/flutter-tflite` does the same. The `libtensorflow` packages on
`storage.googleapis.com` are full TensorFlow, a different API. Third-party
prebuilt binaries exist but are unsigned, unattested and (in the most popular
case) carry no declared license, so they are not suitable to ship.

The scripts build the **C shared library** rather than the static
`tensorflow-lite`: the static one is explicitly not self-contained and drags
every transitive dependency onto the link line, while `tensorflowlite_c` is a
single self-contained artifact.

Tag `v2.17.0` matches the TFLite inside MediaPipe 0.10.35, which is what iOS and
Android use, so the runtime stays aligned across platforms.

### Four upstream fixes are required

These are edits to the TensorFlow source tree, not to this repo. They are applied
by the scripts from [`tools/tflite-v2.17.0-proton.patch`](tools/tflite-v2.17.0-proton.patch);
a different TensorFlow release needs the patch refreshed against it.

1. **C++20.** `tensorflow/lite/CMakeLists.txt` and `tensorflow/lite/c/CMakeLists.txt`
   both hardcode `set(CMAKE_CXX_STANDARD 17)`, which a command-line override
   cannot beat. Newer MSVC rejects the designated initializers in
   `core/c/operator.cc` under C++17 (`error C7555`). Change both to `20`.

2. **Missing exports on Windows.** `tensorflow/lite/CMakeLists.txt` adds
   `-DTFL_STATIC_LIBRARY_BUILD` as a *public* option whenever `BUILD_SHARED_LIBS`
   is off. `tensorflowlite_c` links `tensorflow-lite` and so inherits it, which
   collapses `TFL_CAPI_EXPORT` to nothing — you get a DLL with zero exports and
   no import library, and the failure is silent. Guard it:

   ```cmake
   if (NOT BUILD_SHARED_LIBS AND NOT TFLITE_C_BUILD_SHARED_LIBS)
     list(APPEND TFLITE_TARGET_PUBLIC_OPTIONS "-DTFL_STATIC_LIBRARY_BUILD")
   endif()
   ```

   Verify with `dumpbin /exports tensorflowlite_c.dll` — expect ~98 `TfLite*`
   entries and a generated `tensorflowlite_c.lib`.

3. **Missing opaque C API.** The CMake target omits `core/c/c_api_opaque.cc`
   (the Bazel target includes it), so the accessors a custom-op kernel needs at
   runtime — `TfLiteOpaqueNodeGetInput`, `TfLiteOpaqueTensorData`,
   `TfLiteOpaqueContextResizeTensor` and friends — are absent even though the
   registration functions are present. `selfie_segmenter.tflite` needs a custom
   op (see below), so add it to the `add_library(tensorflowlite_c ...)` sources.
   Exports go from ~98 to ~149.

4. **`TfLiteIntArray` helpers not exported.** `TfLiteOpaqueContextResizeTensor`
   takes a `TfLiteIntArray*`, but `TfLiteIntArrayCreate` and `TfLiteIntArrayFree`
   are declared in `core/c/common.h` without `TFL_CAPI_EXPORT`. Add the macro to
   both. Allocating the array ourselves instead is *not* a safe workaround:
   TFLite frees it internally, and the plugin is built `/MDd` in debug while the
   TFLite DLL is `/MD` release, so the two use different CRT heaps.

Note `cmake --version` matters: CMake 4.x removes compatibility with the
`cmake_minimum_required(VERSION < 3.5)` used by TF 2.17's vendored dependencies
(FP16, psimd). Use CMake 3.2x, or pass `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`.

### Layout expected of `TFLITE_ROOT`

Either a build tree, or a staged directory like the vendored one:

```
<root>/
├── lib/                  tensorflowlite_c.dll + .lib, or libtensorflowlite_c.so
│   └── <abi>/            per-ABI subdirectory; how third_party/tflite is laid out
└── include/  tensorflow/lite/{c,core/c,core/async/c,core}/*.h
              plus tensorflow/lite/builtin_ops.h
```

## Models

`selfie_segmenter.tflite` is copied from `android/src/main/assets/` next to
`libproton_video_effects_plugin.so` / `proton_video_effects_plugin.dll` at build time.

### The model needs a MediaPipe custom op

This model is `selfiesegmentation_mlkit-256x256` and contains one operator that
stock TFLite does not implement, `Convolution2DTransposeBias`. Loading it on a
plain interpreter fails at prepare time:

```
ERROR: Encountered unresolved custom op: Convolution2DTransposeBias.
ERROR: Node number 244 (Convolution2DTransposeBias) failed to prepare.
```

Android does not hit this because MediaPipe registers the op for it. (iOS and
macOS never load this model at all on current OS versions — they default to
Vision's `VNGeneratePersonSegmentationRequest`; MediaPipe is only an iOS
fallback below iOS 15, and the CocoaPod is not used on macOS.)

Desktop therefore has to register the op itself, which
`src/meet_video_effects_custom_ops.cpp` does — ported from MediaPipe's
`transpose_conv_bias.cc` (Apache 2.0) against the opaque C API. A scan of the
model confirms this is the *only* custom op it uses; none of MediaPipe's others
(`MaxPoolingWithArgmax2D`, `MaxUnpooling2D`, `TransformLandmarks`,
`TransformTensorBilinear`, `Landmarks2TransformMatrix`) appear.

## Tests

`test/meet_video_effects_engine_test.cpp` runs the engine against the real model,
so it needs a TFLite runtime and is skipped when none is found. It is the
regression guard for the custom op above. The vendored prebuilt satisfies it, so
on Windows this needs no extra arguments:

```bash
cmake -S plugins/proton_video_effects/native -B build/ve-native -DCMAKE_BUILD_TYPE=Release
cmake --build build/ve-native -j
ctest --test-dir build/ve-native --output-on-failure
```

Add `-DTFLITE_ROOT=/path/to/tflite/dist` to test against a different runtime.

## Frame pipeline (flutter_webrtc)

Desktop publishes a **second track** rather than editing camera frames in place:

1. `DesktopFrameTap` attaches a renderer to the camera track (`MediaTrackForId`
   + `AddRenderer`) and runs each frame through the engine.
2. `CreateProcessedVideoTrack` builds a *custom* video source, wraps it in a
   track, and registers it in `local_tracks_` so Dart can resolve it by id.
3. `PushProcessedFrame` injects composited frames via `OnCapturedFrame`.
4. Dart returns that track from `BackgroundBlurTrackProcessor.processedTrack`;
   LiveKit's `setProcessor` swaps it in, so every existing publish site
   publishes the processed track with no changes.

Both halves are required. Flipping `kDesktopFramePipelineReady` in
`common/desktop/desktop_background_blur.cpp` without the Dart half would offer a
background control whose output is computed and discarded.

### Why not the Apple design

`flutter_webrtc` has no frame-processing seam on desktop. Its
`VideoProcessingAdapter` exists only for Android and Apple, where it works by
being the `RTCVideoCapturer` *delegate*, sitting between capturer and source. On
desktop, `CreateVideoSource(capturer, …)` binds the two inside `libwebrtc.dll`,
the source reference is discarded, `RTCVideoTrack` has no `GetSource()`, and the
desktop `RTCVideoCapturer` exposes only `StartCapture`/`StopCapture` — no frame
delegate at all. So the Apple design cannot be ported as-is.

What *is* reachable from a third-party plugin, following the pattern in
[`livekit_client`'s Windows plugin](https://github.com/livekit/client-sdk-flutter/blob/main/windows/livekit_plugin.cpp):
`flutter_webrtc_plugin.dll` exports only `FlutterWebRTCPluginRegisterWithRegistrar`
and `FlutterWebRTCPluginSharedInstance`, so only **virtual** methods on the
returned instance can be called (vtable dispatch, no linking). That is enough to
observe frames:

| Need | API | Reachable |
|---|---|---|
| Camera track by id | `FlutterWebRTCBase::MediaTrackForId` (virtual) | yes |
| Receive every frame | `RTCVideoTrack::AddRenderer` (virtual) | yes |
| Build a processed frame | `RTCVideoFrame::Create` | yes, exported by `libwebrtc.dll` |
| Injectable source | `CreateCustomVideoSource` + `OnCapturedFrame` (virtual) | yes |
| Swap a published track | `RTCRtpSender::set_track` (virtual) | yes |
| Own/register the track | `factory_`, `local_tracks_` (protected data) | via the shim below |
| Find the sender | `PeerConnectionForId`, `GetRtpSenderById` (non-virtual, unexported) | **no**, and not needed |

### Reaching `factory_` and `local_tracks_`

Both are protected data members, so `desktop_webrtc_internals.cpp` uses the
explicit-template-instantiation idiom (a standard-sanctioned escape from access
control) to obtain pointers-to-member. No fork or patch of `flutter_webrtc` is
involved, but it does depend on `FlutterWebRTCBase`'s layout, so:

- `flutter_webrtc` is pinned; re-verify on every bump.
- `ProbeWebRtcInternals()` sanity-checks the layout at runtime, and
  `CreateProcessedVideoTrack` refuses to run unless it reports `kVerified`.

Finding the RTP sender is unnecessary because LiveKit publishes the processed
track itself, so the swap happens in Dart rather than on the C++ side.
