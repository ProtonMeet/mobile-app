import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:meet/helper/logger.dart';
import 'package:meet/managers/manager.dart' as manager;
import 'package:meet/managers/notification_service.dart';
import 'package:meet/permissions/permission_service.dart';

/// Simplified Android Notification Service for ongoing meetings.
///
/// Designed to be called the moment the user enters a meeting (NOT from
/// app-lifecycle callbacks), so the permission state read here is stable.
/// If any required permission is missing, the call is a safe no-op rather
/// than a crash: Android 13+ POST_NOTIFICATIONS and Android 14+
/// foregroundServiceType runtime checks are validated up-front, and every
/// platform call is guarded against PlatformException.
class AndroidNotificationService implements NotificationService {
  // Notification constants
  static const int _backgroundNotificationId = 9999;
  static const String _channelId = 'meeting_foreground_service_v1';
  static const String _channelName = 'Meeting in Progress';
  static const String _channelDescription =
      'Notifications for ongoing meetings when app is in background';
  static const String _notificationBody = 'Tap to return to meeting';
  static const String _notificationPayload = 'meeting_foreground';

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  /// Tracks whether the foreground-service notification is currently posted
  /// so repeated `showBackgroundNotification(...)` calls become a no-op.
  bool _isShowing = false;

  Future<void> Function()? _onNotificationTapCallback;

  /// Initialize the notification service
  @override
  Future<void> init() async {
    if (_isInitialized) return;

    final androidSettings = const AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    final settings = InitializationSettings(android: androidSettings);

    try {
      await _notificationsPlugin.initialize(
        settings,
        onDidReceiveNotificationResponse: _handleNotificationTap,
      );
    } on PlatformException catch (e) {
      logger.e('[AndroidNotificationService] init plugin failed: $e');
      // Leave _isInitialized as false; show* will retry on next call.
      return;
    }

    final androidImplementation = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidImplementation != null) {
      try {
        const channel = AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.low,
          showBadge: false,
        );
        await androidImplementation.createNotificationChannel(channel);
      } on PlatformException catch (e) {
        logger.w(
          '[AndroidNotificationService] createNotificationChannel failed: $e',
        );
      }

      try {
        final granted = await androidImplementation
            .requestNotificationsPermission();
        if (granted == false) {
          logger.w(
            '[AndroidNotificationService] Notification permission not granted',
          );
        }
      } on PlatformException catch (e) {
        logger.w(
          '[AndroidNotificationService] requestNotificationsPermission failed: $e',
        );
      }
    }

    _isInitialized = true;
  }

  /// Show the persistent in-meeting notification backed by a foreground
  /// service.
  ///
  /// Call once when the user enters the meeting. Safe to call multiple
  /// times — subsequent calls are no-ops while the notification is already
  /// posted.
  ///
  /// The call short-circuits (no-op + warning log) when any precondition is
  /// missing, so it never throws and never crashes:
  /// - POST_NOTIFICATIONS not granted (Android 13+)
  /// - No camera/microphone permission granted (Android 14+ requires the
  ///   declared `foregroundServiceType` to match a runtime-granted
  ///   permission, otherwise `startForeground` raises SecurityException
  ///   from the system server which is uncatchable from Dart).
  @override
  Future<void> showBackgroundNotification({required String roomName}) async {
    if (!_isInitialized) await init();
    if (!_isInitialized) {
      logger.w(
        '[AndroidNotificationService] Skip show: plugin failed to initialize',
      );
      return;
    }

    if (_isShowing) {
      // Already posted; nothing to do.
      return;
    }

    final permissionService = PermissionService();

    final hasNotification = await permissionService.hasNotificationPermission();
    if (!hasNotification) {
      logger.w(
        '[AndroidNotificationService] Skip show: notification permission '
        'not granted',
      );
      return;
    }

    final androidImpl = await _getAndroidImplementation();
    if (androidImpl == null) {
      logger.w(
        '[AndroidNotificationService] Skip show: Android implementation '
        'unavailable',
      );
      return;
    }

    final hasCamera = await permissionService.hasCameraPermission();
    final hasMic = await permissionService.hasMicrophonePermission();

    // Android 14+ validates each foregroundServiceType against a
    // runtime-granted permission. Build the set from currently granted
    // permissions only; if neither media permission is granted we cannot
    // safely call startForegroundService for the manifest-declared types
    // (phoneCall|camera|microphone|mediaProjection), so we bail out
    // instead of risking a SecurityException from the system server.
    final serviceTypes = <AndroidServiceForegroundType>{
      if (hasCamera) AndroidServiceForegroundType.foregroundServiceTypeCamera,
      if (hasMic) AndroidServiceForegroundType.foregroundServiceTypeMicrophone,
    };

    if (serviceTypes.isEmpty) {
      logger.w(
        '[AndroidNotificationService] Skip show: no media permission granted; '
        'cannot start foreground service safely',
      );
      return;
    }

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      ongoing: true,
      autoCancel: false,
      showWhen: false,
      silent: true,
      category: AndroidNotificationCategory.call,
      channelShowBadge: false,
      visibility: NotificationVisibility.public,
      importance: Importance.low,
      priority: Priority.low,
    );

    try {
      await androidImpl.startForegroundService(
        _backgroundNotificationId,
        _notificationTitle(roomName),
        _notificationBody,
        notificationDetails: androidDetails,
        payload: _notificationPayload,
        // startNotSticky avoids a known NPE crash on some OEM ROMs when the
        // system tries to recreate the service after the process is killed.
        startType: AndroidServiceStartType.startNotSticky,
        foregroundServiceTypes: serviceTypes,
      );
      _isShowing = true;
      logger.d(
        '[AndroidNotificationService] Foreground service started (types: '
        '${serviceTypes.length})',
      );
    } on PlatformException catch (e) {
      logger.e(
        '[AndroidNotificationService] startForegroundService failed: $e',
      );
    } catch (e) {
      logger.e(
        '[AndroidNotificationService] startForegroundService unexpected: $e',
      );
    }
  }

  /// Hide foreground service notification.
  ///
  /// Safe to call at any time — idempotent and hardened against
  /// PlatformException raised when the engine channel is already dead
  /// (e.g. during Activity teardown).
  @override
  Future<void> hideBackgroundNotification() async {
    final androidImpl = await _getAndroidImplementation();
    if (androidImpl != null) {
      try {
        await androidImpl.stopForegroundService();
      } on PlatformException catch (e) {
        logger.w(
          '[AndroidNotificationService] stopForegroundService failed '
          '(may already be stopped): $e',
        );
      }
    }

    try {
      await _notificationsPlugin.cancel(_backgroundNotificationId);
    } on PlatformException catch (e) {
      logger.w('[AndroidNotificationService] cancel notification failed: $e');
    }

    _isShowing = false;
  }

  /// Set tap callback
  @override
  void setBackgroundNotificationTapCallback(Future<void> Function()? callback) {
    _onNotificationTapCallback = callback;
  }

  @override
  void clearBackgroundNotificationTapCallback() {
    _onNotificationTapCallback = null;
  }

  Future<AndroidFlutterLocalNotificationsPlugin?>
  _getAndroidImplementation() async {
    return _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
  }

  String _notificationTitle(String roomName) {
    return roomName.isNotEmpty ? 'In Meeting: $roomName' : 'In Meeting';
  }

  Future<void> _handleNotificationTap(NotificationResponse response) async {
    logger.d(
      '[AndroidNotificationService] Notification tapped, payload: ${response.payload}',
    );

    // Always cancel the notification first to prevent it from staying visible (handle the case that the app was killed by user)
    try {
      await hideBackgroundNotification();
      logger.d('[AndroidNotificationService] Notification cancelled');
    } catch (cancelError) {
      logger.e(
        '[AndroidNotificationService] Error cancelling notification: $cancelError',
      );
    }

    // If callback is null, the app was likely killed and restarted by tapping notification
    // In this case, just clear the notification and don't try to execute the callback
    if (_onNotificationTapCallback == null) {
      logger.w(
        '[AndroidNotificationService] Callback is null, app was likely killed. '
        'Notification cleared, not attempting to restore meeting.',
      );
      return;
    }

    // Only execute callback if it exists and payload matches
    if (response.payload == _notificationPayload) {
      try {
        await _onNotificationTapCallback!()
            .timeout(
              const Duration(seconds: 5),
              onTimeout: () {
                logger.w(
                  '[AndroidNotificationService] Notification tap callback timed out',
                );
              },
            )
            .catchError((e) {
              logger.e(
                '[AndroidNotificationService] Error in notification tap callback: $e',
              );
            });
      } catch (e) {
        logger.e(
          '[AndroidNotificationService] Error handling notification tap: $e',
        );
      }
    }
  }

  // ===========================================================================
  // Manager Interface Implementation
  // ===========================================================================

  @override
  Future<void> dispose() async {
    await hideBackgroundNotification();
    _onNotificationTapCallback = null;
  }

  @override
  Future<void> login(String userID) async {
    // optional: track logged in user
  }

  @override
  Future<void> logout() async {
    await hideBackgroundNotification();
    clearBackgroundNotificationTapCallback();
  }

  @override
  Future<void> reload() async {}

  @override
  manager.Priority getPriority() => manager.Priority.level1;
}
