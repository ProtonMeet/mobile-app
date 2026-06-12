# proton_denoise build scripts

Native tooling by backend. Full plugin notes: `[../README.md](../README.md)`.

```
scripts/
  native_build_env.sh         # shared PATH / Rust / Apple cc helpers (dtln + deepfilter)
  link_apple_pod_sources.sh   # pod prepare_command — symlinks common/darwin + cpp into ios|macos
  rnnoise/                    # RNNoise — compiled at pod build time (CMake, no prebuilts)
  dtln/                       # dtln-rs — prebuilt static libs + Apple staging
  deepfilter/                 # DeepFilterNet — prebuilt frameworks / Android .so
```

## Manual builds (prebuilts)

From repo root (`utilities/build-dtln-rs.sh` is a thin wrapper to the dtln script):

```bash
./plugins/proton_denoise/scripts/dtln/build-dtln-rs.sh [macos|ios|android|apple|all]
./plugins/proton_denoise/scripts/deepfilter/build-deepfilter.sh [ios|ios-sim|macos|android]
```

After changing dtln-rs sources or patches, rebuild and commit under `third_party/dtln-rs/lib/`.
Upstream is patched with three files in `dtln/patches/` (staticlib, gate Neon, defer TFLite link).
Run `DTLN_RS_FORCE_REPREPARE=1` if the build tree was prepared before a patch change.

**iOS simulator archs** — default is arm64 only (Apple Silicon Xcode). Universal sim (Intel / CI):

```bash
DTLN_RS_IOS_SIM_ARCHS="arm64 x86_64" ./plugins/proton_denoise/scripts/dtln/build-dtln-rs.sh ios
```

**Verify** a staged Apple lib (optional third arg = slice in a fat archive):

```bash
sh plugins/proton_denoise/scripts/dtln/verify_dtln_apple_lib.sh iphonesimulator \
  plugins/proton_denoise/third_party/dtln-rs/lib/ios/simulator/libdtln.a arm64
```

iOS needs both `libdtln.a` and `libdtln_tflite.a` under `ios/device` and `ios/simulator`. If the TFLite sim lib is missing, the device slice build failed first — check `_dtln_create` / `scripts/dtln/extra/src/ffi.rs` errors in the log.

## Automatic (CocoaPods / Xcode)

| Phase              | Script                                                                                              |
| ------------------ | --------------------------------------------------------------------------------------------------- |
| `prepare_command`  | `link_apple_pod_sources.sh`                                                                         |
| RNNoise static lib | `rnnoise/build_rnnoise_apple.sh` → needs **CMake 3.14+** (`brew install cmake`, or `RNNOISE_CMAKE`) |
| DTLN prebuilts     | `dtln/stage_dtln_apple.sh` — copies/verifies libs from `third_party/dtln-rs/lib/`                   |

DeepFilter is vendored via `prepare_command` + `cocoapods/deepfilter_pod_support.rb`; build prebuilts with `deepfilter/build-deepfilter.sh` before enabling in the podspec.
