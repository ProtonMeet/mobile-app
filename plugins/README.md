# Proton Meet plugins

Local Flutter plugins used by the Meet app. Each plugin lives in its own directory with a `pubspec.yaml` and is referenced from the root app via `path:` dependencies.

## Plugins

| Plugin                                              | What it does                                                             |
| --------------------------------------------------- | ------------------------------------------------------------------------ |
| [`proton_denoise`](proton_denoise/)                 | Microphone denoising (RNNoise, DTLN, DeepFilter on mobile)               |
| [`proton_video_effects`](proton_video_effects/)     | Camera effects — background blur (Vision on Apple, MediaPipe on Android) |
| [`proton_screen_recorder`](proton_screen_recorder/) | Screen capture (iOS / macOS)                                             |

Details, build steps, and native setup are in each plugin’s `README.md`.

## Layout

```
proton_<name>/
├── lib/           Dart API
├── ios/ macos/ android …  Platform glue
├── test/
├── example/       Optional sample app
└── README.md
```

## Adding a plugin

From this directory:

```bash
flutter create --org com.proton --template=plugin \
  --platforms=ios,android,macos,web,linux,windows \
  proton_<name>
```

Then add a `path:` dependency in the root `pubspec.yaml`.

## Adding a platform to an existing plugin

From inside the plugin directory:

```bash
flutter create --platforms=<platform> .
```

## Conventions

- Keep native build logic inside the plugin (podspecs, Gradle, scripts) — avoid app-level Podfile glue.
- Document platform-specific setup in the plugin README.
- Add tests for Dart-facing behavior; use `example/` when manual QA helps.
