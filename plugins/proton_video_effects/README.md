# proton_video_effects

On-device **camera video effects** for Proton Meet — background blur on local WebRTC camera tracks (`flutter_webrtc` / LiveKit).

| Effect                                | Status      | Platforms      |
| ------------------------------------- | ----------- | -------------- |
| Background blur (Vision + Core Image) | Shipped     | iOS, macOS     |
| Background blur (MediaPipe TFLite)    | Shipped     | Android        |
| Background blur (TFLite C++ core)     | Native only | Linux, Windows |
| Custom virtual background             | Testing     | All            |

## Segmentation defaults

Applied once per process on first attach (`applyPlatformDefaultSegmentationModel`):

| Platform    | Backend                                                   |
| ----------- | --------------------------------------------------------- |
| iOS / macOS | Apple Vision (`VNGeneratePersonSegmentation`)             |
| Android     | MediaPipe landscape (`selfie_segmenter_landscape.tflite`) |

Override for debug via `setSegmentationModelPreference` — see `SegmentationModelPreference`.

## Production blur tuning

Defaults live in `BackgroundBlurConfig` (used by Meet via `const BackgroundBlurConfig()`):

| Parameter                  | Default                                                  |
| -------------------------- | -------------------------------------------------------- |
| `blurSigma`                | 128 (Gaussian σ on Apple; mapped to box blur on Android) |
| `backgroundObscureOpacity` | 0.1                                                      |

## Dart API

All native communication goes through `**ProtonVideoEffects.instance`\*\*. Method-channel code is internal (`lib/src/`).

```
lib/
├── proton_video_effects.dart           # facade — use this
├── background_blur_config.dart         # blur tuning
├── background_blur_track_processor.dart # LiveKit TrackProcessor
├── segmentation_model_preference.dart
├── segmentation_model_debug_info.dart
├── camera_background_mode.dart
└── src/proton_video_effects_channel.dart   # internal
```

## App usage

```yaml
dependencies:
  proton_video_effects:
    path: plugins/proton_video_effects
```

`flutter_webrtc` / `livekit_client` versions are resolved with the Meet app workspace — bump them in the root `pubspec.yaml`, not separately here.

```dart
import 'package:proton_video_effects/proton_video_effects.dart';

if (!ProtonVideoEffects.isSupported) return;

const config = BackgroundBlurConfig(); // σ=128, obscure=0.1

// LiveKit — attach at track creation (Meet production path)
final processor = ProtonVideoEffects.instance.createBlurTrackProcessor(
  config: config,
);
LocalVideoTrack.createCameraTrack(
  CameraCaptureOptions(processor: processor),
);

// Or attach / detach on an existing track
await ProtonVideoEffects.instance.attachBackgroundBlur(
  trackId: trackId,
  config: config,
);
await ProtonVideoEffects.instance.detachBackgroundBlur(trackId: trackId);

// Runtime tuning
await ProtonVideoEffects.instance.setBackgroundBlurConfig(config);
```

Do **not** construct `BackgroundBlurTrackProcessor` directly — use `createBlurTrackProcessor()` so the processor shares the facade's channel client.

## Native layout

```
proton_video_effects/
├── lib/                 Dart facade + models
├── darwin/Classes/      Shared iOS + macOS blur pipeline
├── ios/                 Plugin registration + TFLite assets (Android segmenter N/A)
├── macos/               FlutterMacOS plugin
├── android/             Kotlin MediaPipe pipeline + assets
├── native/              TFLite C++ core (Linux / Windows)
├── linux/ windows/      Desktop plugin glue
└── scripts/             Model fetch / desktop TFLite build
```

## Linux / Windows

1. Build TFLite — [native/README.md](native/README.md) or `scripts/build_tflite_desktop.sh`.
2. Build Meet with `-DTFLITE_ROOT=/path/to/tflite-build`.
3. `isBackgroundBlurReady` is true when the model loads next to the plugin library.

The CPU segmentation + blur pipeline mirrors Android. Wiring processed frames into the **encoder path** still needs a desktop `VideoProcessingAdapter` in `flutter_webrtc`; the native engine exposes `meet_video_effects_process_i420()` for that hook.

## Custom background

Still-image replacement is enabled (`BackgroundBlurConfig.replacementBackgroundEnabled = true`): an image supplied by path or bytes is composited through the same segmentation mask as blur. Callers set it with `setReplacementBackgroundImagePath` / `setReplacementBackgroundImageBytes` and drop it with `clearReplacementBackground`, which also releases the decoded copy the engine caches.
