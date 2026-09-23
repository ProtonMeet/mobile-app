# Vendored TensorFlow Lite C runtime

Prebuilt TensorFlow Lite C API, committed so that building the app does not
require building TensorFlow. `native/CMakeLists.txt` picks this up automatically;
nothing has to be installed or configured.

## Provenance

| | |
|---|---|
| Upstream | <https://github.com/tensorflow/tensorflow> |
| Release | `v2.17.0` |
| Commit | `ad6d8cc177d0c868982e39e0823d0efbfb95f04c` |
| Local patch | [`../../tools/tflite-v2.17.0-proton.patch`](../../tools/tflite-v2.17.0-proton.patch) |
| CMake source dir | `tensorflow/lite/c` |
| Configuration | `-DCMAKE_BUILD_TYPE=Release -DTFLITE_C_BUILD_SHARED_LIBS=ON`, Ninja |
| Licence | Apache 2.0 — see [`LICENSE`](LICENSE) |

`windows-x64` was built with MSVC 19.51 (Visual Studio 2022 toolset, x64).

## Layout

```
include/                      C API headers, shared by all platforms
lib/windows-x64/              tensorflowlite_c.dll  (runtime, bundled next to the app)
                              tensorflowlite_c.lib  (import library, link time)
lib/linux-x64/                libtensorflowlite_c.so   — NOT YET COMMITTED, see below
```

Libraries are per platform and architecture, and the build only ever looks in
the directory for the ABI it is building. An ABI with no directory here is not a
silent fallback: the plugin configures with blur disabled and CMake says so.

The headers are shared because the same tag plus the same patch produce
byte-identical headers regardless of which platform stages them. They must stay
in step with the libraries — a header refresh without a matching rebuild of every
library in `lib/` is an ABI mismatch.

## Linux is not populated yet

`lib/linux-x64/libtensorflowlite_c.so` has to be produced on a Linux machine (or
in CI); it cannot be cross-built from Windows. Until it is committed, Linux
builds compile and run with background blur disabled.

To produce and commit it:

```sh
plugins/proton_video_effects/native/tools/build_tflite.sh
```

## Refreshing or upgrading

Run the script for the platform you are on:

```powershell
plugins\proton_video_effects\native\tools\build_tflite.ps1      # Windows
```
```sh
plugins/proton_video_effects/native/tools/build_tflite.sh       # Linux
```

Both clone the pinned tag, apply the patch, build, and stage the result here.
Moving to a new TensorFlow release needs a patch refreshed against that release
(`tflite-<ref>-proton.patch`) and every platform's library rebuilt together.
See [`../../README.md`](../../README.md) for what each patch hunk does and why it
is needed.
