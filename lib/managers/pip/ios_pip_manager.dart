import 'dart:async';

import 'package:meet/helper/logger.dart';
import 'package:meet/managers/channels/picture_in_picture_channel.dart';
import 'package:meet/managers/pip/ios_pip_presentation.dart';
import 'package:meet/managers/pip/pip_manager_interface.dart';

/// iOS PiP via `AVPictureInPictureController` + flutter-webrtc (`PipManager.swift`).
class IosPipManager implements PipManagerInterface {
  final PictureInPictureChannel _channel = PictureInPictureChannel();

  final StreamController<bool> _pipStateController =
      StreamController<bool>.broadcast();

  bool _initialized = false;
  bool _isPipActive = false;

  IosPipPresentation? _pendingPresentation;

  Future<void> setPresentation(IosPipPresentation presentation) async {
    _pendingPresentation = presentation;
    if (!_initialized) {
      return;
    }
    await _attachCurrentPresentation();
  }

  Future<void> _attachCurrentPresentation() async {
    final presentation = _pendingPresentation;
    if (presentation == null) {
      return;
    }
    await _channel.attachPipForPresentation(presentation);
  }

  @override
  Stream<bool> get pipStateStream => _pipStateController.stream;

  @override
  Future<bool> isPipAvailable() async {
    return _channel.isPipSupported();
  }

  @override
  Future<bool> isPipSupported() async {
    return _channel.isPipSupported();
  }

  @override
  Future<bool> isPipActivated() async {
    return _isPipActive;
  }

  @override
  Future<void> initialize({
    required String roomName,
    required Future<void> Function() onPipEntered,
    required Future<void> Function() onPipExited,
    required Future<void> Function() onNotificationTap,
  }) async {
    if (_initialized) {
      return;
    }

    _channel.listenPipState(({required bool isActive}) {
      _isPipActive = isActive;
      _pipStateController.add(isActive);
    });

    try {
      await _channel.preparePip();
    } catch (e) {
      logger.w('[IosPipManager] preparePiP failed (non-fatal): $e');
    }

    _initialized = true;
    await _attachCurrentPresentation();
  }

  @override
  Future<bool> enterPipMode() async {
    if (!_initialized) {
      logger.w('[IosPipManager] PIP not initialized');
      return false;
    }

    if (_pendingPresentation == null) {
      logger.w('[IosPipManager] Missing PiP presentation for active speaker');
      return false;
    }

    try {
      final supported = await _channel.isPipSupported();
      if (!supported) {
        return false;
      }

      await _attachCurrentPresentation();
      await _channel.startPipWindow();
      return true;
    } catch (e, stack) {
      logger.e('[IosPipManager] enterPipMode failed: $e');
      logger.e('[IosPipManager] $stack');
      return false;
    }
  }

  @override
  Future<void> updatePipVideoTrack() async {
    if (!_initialized) {
      return;
    }

    try {
      await _attachCurrentPresentation();
    } catch (e) {
      logger.e('[IosPipManager] updatePipVideoTrack failed: $e');
    }
  }

  @override
  Future<void> exitPipMode() async {
    try {
      await _channel.stopPip();
    } catch (e) {
      logger.e('[IosPipManager] exitPipMode failed: $e');
    } finally {
      _isPipActive = false;
      _pipStateController.add(false);
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _channel.disposePip();
    } catch (e) {
      logger.e('[IosPipManager] dispose failed: $e');
    }
    _isPipActive = false;
    _pendingPresentation = null;
    _initialized = false;
    await _pipStateController.close();
  }
}
