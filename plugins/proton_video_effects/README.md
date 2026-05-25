# proton_video_effects

On-device **camera video effects** for Proton Meet via `flutter_webrtc` local video tracks.

| Effect                                            | Status                | Platforms           |
| ------------------------------------------------- | --------------------- | ------------------- |
| Background blur (MediaPipe / Vision + Core Image) | Shipped               | iOS, Android, macOS |
| Background blur (TensorFlow Lite)                 | Shipped (native core) | Linux, Windows      |
| Custom virtual background                         | Roadmap               | TBD                 |

## Layout

```
proton_video_effects/
├── lib/                    # Dart channel + LiveKit TrackProcessor
├── darwin/Classes/         # Shared iOS + macOS MediaPipe / Core Image pipeline
├── ios/Classes/            # Flutter plugin registration
├── ios/Resources/*.tflite
├── macos/                  # FlutterMacOS (darwin/ + Apple Vision segmentation)
├── android/                # Kotlin pipeline + assets
├── native/                 # TensorFlow Lite C++ core (Linux/Windows)
├── linux/                  # Flutter plugin + channel
└── windows/                # Flutter plugin + channel
```

## App usage

```yaml
dependencies:
  proton_video_effects:
    path: plugins/proton_video_effects
```

```dart
import 'package:proton_video_effects/proton_video_effects.dart';

// Toggle on existing track
await ProtonVideoEffects.instance.attachBackgroundBlur(trackId: id);

// Or via LiveKit when creating the camera track
LocalVideoTrack.createCameraTrack(
  CameraCaptureOptions(
    processor: BackgroundBlurTrackProcessor(),
  ),
);
```

## Linux / Windows (TensorFlow Lite)

1. Build TFLite — see [native/README.md](native/README.md) or `scripts/build_tflite_desktop.sh`.
2. Build Meet with `-DTFLITE_ROOT=/path/to/tflite-build` (CMake).
3. `isBackgroundBlurReady` is true when the model loads from the path next to the plugin library.

The segmentation + blur CPU pipeline mirrors Android (720p cap, pooled I420). Wiring processed
frames into the **encoder path** requires a desktop `VideoProcessingAdapter` in `flutter_webrtc`
(tracked separately); the native engine exposes `meet_video_effects_process_i420()` for that hook.

## Future: custom background

Planned channel methods (not implemented yet): supply a background image path/bytes and composite via the same segmentation mask used for blur. Extend [VideoEffectKind.customBackground] in `proton_video_effects_channel.dart`.
