import 'dart:async';
import 'package:flutter/services.dart';
import 'package:meet/helper/logger.dart';
import 'package:meet/managers/manager.dart' as manager;
import 'package:meet/managers/notification_service.dart';
import 'package:meet/permissions/permission_service.dart';

/// Android ongoing meeting via native foreground service.
///
/// Uses [MeetCallForegroundService] with [NotificationCompat.CallStyle] and
/// [MediaSession] instead of [flutter_local_notifications].
class AndroidNotificationService implements NotificationService {
  static const _channel = MethodChannel('proton.android.meet/meeting_call');

  bool _isInitialized = false;
  bool _isMeetingCallActive = false;
  bool _isScreenShareForegroundActive = false;

  /// Serializes native FGS start/stop to avoid stop/start races (e.g. permission
  /// grant + screen-share upgrade overlapping with meeting notification start).
  Future<void> _fgsQueue = Future<void>.value();

  Future<void> Function()? _onNotificationTapCallback;
  Future<void> Function()? _onEndCallCallback;

  Future<T> _runSerializedFgs<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _fgsQueue = _fgsQueue.then((_) async {
      try {
        if (!completer.isCompleted) {
          completer.complete(await action());
        }
      } catch (e, st) {
        if (!completer.isCompleted) {
          completer.completeError(e, st);
        }
      }
    });
    return completer.future;
  }

  void _ensureMethodCallHandler() {
    _channel.setMethodCallHandler(_onNativeMethodCall);
  }

  @override
  Future<void> init() async {
    _ensureMethodCallHandler();
    if (_isInitialized) return;

    try {
      final ok = await _channel.invokeMethod<bool>('init');
      _isInitialized = ok == true;
      if (!_isInitialized) {
        logger.w('[AndroidNotificationService] Native init failed');
      }
    } on PlatformException catch (e) {
      logger.e('[AndroidNotificationService] init failed: $e');
    }
  }

  Future<void> _onNativeMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onReturnToCall':
        try {
          await _onNotificationTapCallback?.call();
        } catch (e) {
          logger.e('[AndroidNotificationService] onReturnToCall failed: $e');
        }
        break;
      case 'onEndCallRequested':
        if (_onEndCallCallback == null) {
          logger.w(
            '[AndroidNotificationService] onEndCallRequested: no callback',
          );
          return;
        }
        try {
          await _onEndCallCallback!.call();
        } catch (e) {
          logger.e('[AndroidNotificationService] onEndCall failed: $e');
        }
        break;
      default:
        break;
    }
  }

  @override
  Future<void> showBackgroundNotification({
    required String roomName,
    String? callId,
    bool requestPermissionIfMissing = true,
  }) async {
    if (_isScreenShareForegroundActive) {
      logger.d(
        '[AndroidNotificationService] Skip start: screen-share FGS active',
      );
      return;
    }

    await _runSerializedFgs(
      () => _startMeetingForegroundUnlocked(
        roomName: roomName,
        callId: callId,
        requestPermissionIfMissing: requestPermissionIfMissing,
      ),
    );
  }

  /// Must run inside [_runSerializedFgs] (or from another unlocked caller on
  /// the same queue).
  Future<void> _startMeetingForegroundUnlocked({
    required String roomName,
    String? callId,
    bool requestPermissionIfMissing = true,
  }) async {
    if (_isScreenShareForegroundActive) {
      return;
    }

    if (!_isInitialized) await init();
    if (!_isInitialized) {
      logger.w('[AndroidNotificationService] Skip: not initialized');
      return;
    }

    if (_isMeetingCallActive) {
      return;
    }

    if (!await _ensureNotificationPermission(
      requestIfMissing: requestPermissionIfMissing,
    )) {
      return;
    }

    final permissionService = PermissionService();

    final effectiveCallId =
        (callId != null && callId.isNotEmpty) ? callId : roomName;
    if (effectiveCallId.isEmpty) {
      logger.w('[AndroidNotificationService] Skip: empty callId');
      return;
    }

    final hasCamera = await permissionService.hasCameraPermission();
    final hasMic = await permissionService.hasMicrophonePermission();

    try {
      final started = await _channel.invokeMethod<bool>('startMeeting', {
        'callId': effectiveCallId,
        'roomName': roomName,
        'hasCamera': hasCamera,
        'hasMic': hasMic,
      });
      _isMeetingCallActive = started == true;
      if (_isMeetingCallActive) {
        logger.i(
          '[AndroidNotificationService] Meeting foreground service started',
        );
      } else {
        logger.e('[AndroidNotificationService] startMeeting returned false');
      }
    } on PlatformException catch (e) {
      logger.e('[AndroidNotificationService] startMeeting failed: $e');
    }
  }

  @override
  Future<bool> startScreenShareForegroundService({
    required String roomName,
  }) async {
    return _runSerializedFgs(() async {
      if (!_isInitialized) await init();
      if (!_isInitialized) return false;

      if (!await _ensureNotificationPermission(requestIfMissing: false)) {
        return false;
      }

      // Screen-share FGS upgrade requires an active meeting FGS on native side.
      if (!_isMeetingCallActive) {
        logger.w(
          '[AndroidNotificationService] Meeting FGS inactive before '
          'screen-share upgrade; starting meeting FGS first',
        );
        await _startMeetingForegroundUnlocked(
          roomName: roomName,
          requestPermissionIfMissing: false,
        );
        if (!_isMeetingCallActive) {
          logger.e(
            '[AndroidNotificationService] Cannot upgrade: meeting FGS '
            'failed to start',
          );
          return false;
        }
      }

      try {
        final ok = await _channel.invokeMethod<bool>('startScreenShare');
        if (ok == true) {
          _isScreenShareForegroundActive = true;
          logger.i('[AndroidNotificationService] Screen-share FGS upgraded');
        }
        return ok == true;
      } on PlatformException catch (e) {
        logger.e('[AndroidNotificationService] startScreenShare failed: $e');
        return false;
      }
    });
  }

  @override
  Future<void> stopScreenShareForegroundService({
    required String roomName,
  }) async {
    if (!_isScreenShareForegroundActive && !_isMeetingCallActive) {
      return;
    }

    await _runSerializedFgs(() async {
      _isScreenShareForegroundActive = false;
      try {
        await _channel.invokeMethod<void>('stopScreenShare');
        logger.d('[AndroidNotificationService] Screen-share FGS downgraded');
      } on PlatformException catch (e) {
        logger.e('[AndroidNotificationService] stopScreenShare failed: $e');
      }
    });
  }

  @override
  Future<void> hideBackgroundNotification() async {
    await _runSerializedFgs(() async {
      _isScreenShareForegroundActive = false;
      _isMeetingCallActive = false;
      try {
        await _channel.invokeMethod<void>('stopMeeting');
        logger.d(
          '[AndroidNotificationService] Meeting foreground service stopped',
        );
      } on PlatformException catch (e) {
        logger.w('[AndroidNotificationService] stopMeeting failed: $e');
      }
    });
  }

  @override
  void setBackgroundNotificationTapCallback(Future<void> Function()? callback) {
    _onNotificationTapCallback = callback;
  }

  /// Called when the user ends the meeting from the system call notification.
  void setEndCallFromNotificationCallback(Future<void> Function()? callback) {
    _ensureMethodCallHandler();
    _onEndCallCallback = callback;
  }

  @override
  void clearBackgroundNotificationTapCallback() {
    _onNotificationTapCallback = null;
    _onEndCallCallback = null;
  }

  @override
  Future<void> dispose() async {
    await hideBackgroundNotification();
    _onNotificationTapCallback = null;
    _onEndCallCallback = null;
    _channel.setMethodCallHandler(null);
    _isInitialized = false;
  }

  @override
  Future<void> login(String userID) async {}

  @override
  Future<void> logout() async {
    await hideBackgroundNotification();
    clearBackgroundNotificationTapCallback();
  }

  @override
  Future<void> reload() async {}

  @override
  manager.Priority getPriority() => manager.Priority.level1;

  /// Android 13+ requires [POST_NOTIFICATIONS] before [startForeground].
  Future<bool> _ensureNotificationPermission({
    bool requestIfMissing = true,
  }) async {
    final permissionService = PermissionService();
    if (await permissionService.hasNotificationPermission()) {
      return true;
    }
    if (!requestIfMissing) {
      logger.w(
        '[AndroidNotificationService] Notification permission not granted',
      );
      return false;
    }
    logger.i(
      '[AndroidNotificationService] Requesting notification permission',
    );
    final granted = await permissionService.ensureNotificationPermission();
    if (!granted) {
      logger.w(
        '[AndroidNotificationService] Notification permission denied; '
        'cannot show meeting notification',
      );
    }
    return granted;
  }
}
