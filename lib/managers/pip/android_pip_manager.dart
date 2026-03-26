// ignore_for_file: unused_field

import 'dart:async';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/helper/logger.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/notification_service.dart';
import 'package:meet/managers/pip/pip_manager_interface.dart';
import 'package:simple_pip_mode/simple_pip.dart';

/// Android implementation of PIP manager
class AndroidPipManager implements PipManagerInterface {
  SimplePip? _simplePip;
  bool? _pipAvailable;
  bool _isInitialized = false;
  String? _roomName;
  Future<void> Function()? _onPipEntered;
  Future<void> Function()? _onPipExited;
  Future<void> Function()? _onNotificationTap;

  final _pipStateController = StreamController<bool>.broadcast();
  bool _isPipActive = false;

  @override
  Stream<bool> get pipStateStream => _pipStateController.stream;

  @override
  Future<bool> isPipAvailable() async {
    if (_pipAvailable != null) {
      return _pipAvailable!;
    }

    try {
      _pipAvailable = await SimplePip.isPipAvailable;
      return _pipAvailable == true;
    } catch (e) {
      logger.e('[AndroidPipManager] Error checking PIP availability: $e');
      _pipAvailable = false;
      return false;
    }
  }

  @override
  Future<bool> isPipSupported() async {
    // Only Android supports PIP
    if (!android) {
      return false;
    }

    // Check if PIP is available on device
    return isPipAvailable();
  }

  @override
  Future<bool> isPipActivated() async {
    try {
      return await SimplePip.isPipActivated;
    } catch (e) {
      logger.e('[AndroidPipManager] Error checking PIP activated status: $e');
      return false;
    }
  }

  @override
  Future<void> initialize({
    required String roomName,
    required Future<void> Function() onPipEntered,
    required Future<void> Function() onPipExited,
    required Future<void> Function() onNotificationTap,
  }) async {
    if (_isInitialized) {
      return;
    }

    _roomName = roomName;
    _onPipEntered = onPipEntered;
    _onPipExited = onPipExited;
    _onNotificationTap = onNotificationTap;

    try {
      final notificationService = ManagerFactory().get<NotificationService>();

      await notificationService.init();
      notificationService.setBackgroundNotificationTapCallback(
        onNotificationTap,
      );

      final available = await isPipAvailable();
      if (available) {
        _simplePip = SimplePip(
          onPipEntered: () async {
            _isPipActive = true;
            _pipStateController.add(true);
            await onPipEntered();
          },
          onPipExited: () async {
            _isPipActive = false;
            _pipStateController.add(false);
            await onPipExited();
          },
        );
      }

      _isInitialized = true;
    } catch (e, stackTrace) {
      logger.e('[AndroidPipManager] PIP initialization failed: $e');
      logger.e('[AndroidPipManager] Stack trace: $stackTrace');
      _pipAvailable = false;
      rethrow;
    }
  }

  @override
  Future<bool> enterPipMode() async {
    if (!_isInitialized) {
      logger.w('[AndroidPipManager] PIP not initialized');
      return false;
    }

    if (_isPipActive) {
      return true;
    }

    try {
      // Check if PIP is available
      final available = await isPipAvailable();
      if (!available) {
        logger.w(
          '[AndroidPipManager] PIP not available, showing notification instead',
        );
        await _showNotificationFallback();
        return false;
      }

      if (_simplePip == null) {
        logger.e(
          '[AndroidPipManager] SimplePip is null even though PIP is available!',
        );
        await _showNotificationFallback();
        return false;
      }

      // Check current PIP status
      final isActivated = await isPipActivated();
      if (isActivated) {
        _isPipActive = true;
        _pipStateController.add(true);
        return true;
      }

      // Enter PIP mode
      await _simplePip!.enterPipMode();
      return true;
    } catch (e) {
      logger.e('[AndroidPipManager] Error entering PIP mode: $e');
      await _showNotificationFallback();
      return false;
    }
  }

  @override
  Future<void> exitPipMode() async {
    if (!_isInitialized) {
      return;
    }

    try {
      _isPipActive = false;
      _pipStateController.add(false);
    } catch (e) {
      logger.e('[AndroidPipManager] Error exiting PIP mode: $e');
    }
  }

  @override
  Future<void> dispose() async {
    await exitPipMode();
    _simplePip = null;
    _isInitialized = false;
    _roomName = null;
    _onPipEntered = null;
    _onPipExited = null;
    _onNotificationTap = null;

    final notificationService = ManagerFactory().get<NotificationService>();
    notificationService.clearBackgroundNotificationTapCallback();

    await _pipStateController.close();
  }

  Future<void> _showNotificationFallback() async {
    if (_roomName == null) {
      return;
    }

    try {
      final notificationService = ManagerFactory().get<NotificationService>();
      await notificationService.showBackgroundNotification(
        roomName: _roomName!,
      );
    } catch (e) {
      logger.e('[AndroidPipManager] Error showing notification: $e');
    }
  }
}
