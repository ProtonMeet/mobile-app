import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Events emitted by the native screen recorder.
enum ScreenRecorderEvent {
  /// Recording was stopped externally (e.g. system menu bar on macOS).
  stopped,

  /// iOS ReplayKit capture ended while the app was backgrounded.
  interrupted,

  /// ReplayKit availability changed (macOS only).
  availabilityChanged,
}

/// Thrown when screen recording is not available on the current platform.
class ScreenRecordingNotSupportedException implements Exception {
  const ScreenRecordingNotSupportedException([this.message]);

  final String? message;

  @override
  String toString() =>
      message ?? 'Screen recording is not supported on this platform';
}

/// Cross-platform screen recording API.
///
/// iOS, macOS, and Android use native capture. Other platforms return
/// [isSupported] == false until native capture is implemented.
class ProtonScreenRecorder {
  ProtonScreenRecorder();

  static const MethodChannel _channel = MethodChannel('screen_recording');
  static const EventChannel _eventChannel =
      EventChannel('screen_recording/events');

  Stream<ScreenRecorderEvent>? _eventStream;

  /// Whether the current platform has a screen-recording implementation.
  Future<bool> isSupported() async {
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.android:
        try {
          final supported =
              await _channel.invokeMethod<bool>('isSupported') ?? false;
          return supported;
        } on PlatformException {
          return false;
        }
      default:
        return false;
    }
  }

  /// Whether a recording session is currently active.
  Future<bool> isRecording() async {
    if (!await isSupported()) return false;
    try {
      return await _channel.invokeMethod<bool>('isRecording') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Stream of native recorder events (stop from system UI, availability).
  Stream<ScreenRecorderEvent> events() {
    _eventStream ??= _eventChannel.receiveBroadcastStream().where((event) {
      return event == 'recordingStopped' ||
          event == 'recordingInterrupted' ||
          event == 'recordingAvailabilityChanged';
    }).map((event) {
      if (event == 'recordingStopped') {
        return ScreenRecorderEvent.stopped;
      }
      if (event == 'recordingInterrupted') {
        return ScreenRecorderEvent.interrupted;
      }
      return ScreenRecorderEvent.availabilityChanged;
    }).handleError((_) {});
    return _eventStream!;
  }

  /// Starts screen recording with microphone enabled.
  ///
  /// When [outputPath] is set, native capture writes incrementally to that file
  /// (macOS 13.0+ / iOS). Without a path, ReplayKit preview UI is used on stop.
  Future<void> startRecording({
    bool enableAudio = true,
    bool enableMicrophone = true,
    String? outputPath,
  }) async {
    if (!await isSupported()) {
      throw const ScreenRecordingNotSupportedException();
    }
    try {
      await _channel.invokeMethod<void>('startRecording', {
        'enableAudio': enableAudio,
        'enableMicrophone': enableMicrophone,
        if (outputPath != null) 'outputPath': outputPath,
      });
    } on PlatformException catch (e) {
      throw Exception('Failed to start recording: ${e.message}');
    }
  }

  /// Stops screen recording.
  ///
  /// Returns the saved file path when file-based capture was used; otherwise
  /// null (user saves via ReplayKit preview on iOS / legacy macOS path).
  Future<String?> stopRecording() async {
    try {
      return await _channel.invokeMethod<String>('stopRecording');
    } on PlatformException catch (e) {
      throw Exception('Failed to stop recording: ${e.message}');
    }
  }

  /// Copies a completed recording into public Downloads/Proton Meet (Android).
  Future<String?> publishToDownloads({
    required String sourcePath,
    required String displayName,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }
    try {
      return await _channel.invokeMethod<String>('publishToDownloads', {
        'sourcePath': sourcePath,
        'displayName': displayName,
      });
    } on PlatformException {
      return null;
    }
  }
}
