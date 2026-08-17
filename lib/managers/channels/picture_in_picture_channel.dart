import 'dart:async';

import 'package:flutter/services.dart';
import 'package:meet/managers/pip/ios_pip_presentation.dart';

/// Platform channel for Picture-in-Picture (PiP) functionality on iOS
class PictureInPictureChannel {
  static const _pipChannel = MethodChannel('pip_channel');
  static const _pipEvents = MethodChannel('pip_events');

  Future<bool> isPipSupported() async {
    try {
      final v = await _pipChannel.invokeMethod<bool>('isPipSupported');
      return v ?? false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  void listenPipState(void Function({required bool isActive}) onChanged) {
    _pipEvents.setMethodCallHandler((call) async {
      if (call.method == 'pipStateChanged') {
        final active = call.arguments == true;
        onChanged(isActive: active);
      }
    });
  }

  Future<void> attachPipForPresentation(IosPipPresentation presentation) async {
    await _pipChannel.invokeMethod(
      'attachPiP',
      presentation.toMethodChannelArgs(),
    );
  }

  Future<void> startPipWindow() async {
    await _pipChannel.invokeMethod('startPiP');
  }

  /// Sends the app to the home screen after PiP starts (iOS only).
  Future<void> moveAppToBackground() async {
    await _pipChannel.invokeMethod('moveAppToBackground');
  }

  Future<void> updatePipForPresentation(IosPipPresentation presentation) async {
    await _pipChannel.invokeMethod(
      'updatePiP',
      presentation.toMethodChannelArgs(),
    );
  }

  Future<void> preparePip() async {
    await _pipChannel.invokeMethod('preparePiP');
  }

  Future<void> stopPip() async {
    await _pipChannel.invokeMethod('stopPiP');
  }

  Future<void> disposePip() async {
    await _pipChannel.invokeMethod('disposePiP');
  }
}
