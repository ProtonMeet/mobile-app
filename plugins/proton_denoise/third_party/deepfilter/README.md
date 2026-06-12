# DeepFilter native artifacts (libDF)

All prebuilts live here. `prepare_command` symlinks vendored binaries and the model
into each platform pod root (`ios/Vendored`, `ios/Resources`, etc.).
directly. A Podfile post-install hook embeds frameworks and the model bundle because
CocoaPods does not copy vendored paths outside the platform pod root automatically.

```
third_party/deepfilter/
  include/deep_filter.h              C API header
  models/
    DeepFilterNet3_onnx.tar.gz       bundled model
  lib/
    android/<abi>/libdeepfilter.so   Android JNI (Gradle jniLibs)
  ios/DeepFilter.xcframework         iOS ship artifact
  macos/DeepFilter.framework         macOS ship artifact (versioned bundle)
```

Apple `.dylib` slices are **not** stored here. They are build-only intermediates under
`.local/deepfilter-staging/apple/` when running `./plugins/proton_denoise/scripts/deepfilter/build-deepfilter.sh`.
The xcframework / framework contain the same binaries, repackaged for Xcode/CocoaPods.

Rebuild:

```bash
./plugins/proton_denoise/scripts/deepfilter/build-deepfilter.sh ios
./plugins/proton_denoise/scripts/deepfilter/build-deepfilter.sh ios-sim
./plugins/proton_denoise/scripts/deepfilter/build-deepfilter.sh macos
./plugins/proton_denoise/scripts/deepfilter/build-deepfilter.sh android
```
