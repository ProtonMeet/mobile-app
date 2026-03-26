import 'dart:async';
import 'package:flutter/services.dart';

/// Platform channel for Picture-in-Picture (PiP) functionality on iOS
class PictureInPictureChannel {
  static const _pipChannel = MethodChannel('pip_channel');
  Future<void> startPipForRemoteTrack({
    required String remoteStreamId,
    required String peerConnectionId,
  }) async {
    await _pipChannel.invokeMethod('startPiP', {
      'remoteStreamId': remoteStreamId,
      'peerConnectionId': peerConnectionId,
    });
  }

  Future<void> stopPip() async {
    await _pipChannel.invokeMethod('stopPiP');
  }

  Future<void> disposePip() async {
    await _pipChannel.invokeMethod('disposePiP');
  }
}
