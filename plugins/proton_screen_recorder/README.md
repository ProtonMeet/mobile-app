# Proton Screen Recorder

A macOS-only Flutter plugin for screen recording in Proton Meet.

## Features

- Start screen recording
- Stop screen recording
- Save recording to a temporary file
- High-quality H.264 video encoding
- 1280x720 resolution

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  proton_screen_recorder:
    path: ../plugins/proton_screen_recorder
```

## Usage

```dart
import 'package:proton_screen_recorder/proton_screen_recorder.dart';

// Start recording
final bool started = await ProtonScreenRecorder.startRecording();
if (started) {
  print('Recording started');
}

// Stop recording
final String? filePath = await ProtonScreenRecorder.stopRecording();
if (filePath != null) {
  print('Recording saved to: $filePath');
}
```

## Requirements

- macOS 10.15 or later
- Flutter 3.29.0 or later

## Notes

- The plugin currently saves recordings to `/tmp/screen_recording.mov`
- Screen recording requires screen capture permission
- The plugin is macOS-only and will not work on other platforms
