import 'dart:async';
import 'package:flutter/services.dart';

class ProtonScreenRecorder {
  static const MethodChannel _channel = MethodChannel('screen_recording');

  /// Starts screen recording
  ///
  /// Returns true if recording started successfully, false otherwise
  Future<void> startRecording() async {
    try {
      await _channel.invokeMethod('startRecording', {
        'enableAudio': true, // Enable system audio
        'enableMicrophone': true, // Enable microphone
      });
    } on PlatformException catch (e) {
      throw Exception('Failed to start recording: ${e.message}');
    }
  }

  /// Stops screen recording
  ///
  /// Returns the path to the recorded file if successful, null otherwise
  Future<String?> stopRecording() async {
    try {
      final String? path = await _channel.invokeMethod('stopRecording');
      return path;
    } on PlatformException catch (e) {
      throw Exception('Failed to stop recording: ${e.message}');
    }
  }
}
