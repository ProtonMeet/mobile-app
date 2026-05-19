import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:meet/helper/logger.dart';
import 'package:meet/managers/manager.dart' as manager;
import 'package:meet/managers/notification_service.dart';
import 'package:meet/permissions/permission_service.dart';

/// Simplified Android Notification Service for ongoing meetings
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

  Future<void> Function()? _onNotificationTapCallback;

  /// Initialize the notification service
  @override
  Future<void> init() async {
    if (_isInitialized) return;

    final androidSettings = const AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    final settings = InitializationSettings(android: androidSettings);

    await _notificationsPlugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _handleNotificationTap,
    );

    final androidImplementation = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidImplementation != null) {
      // Create notification channel
      const channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.low,
        showBadge: false,
      );
      await androidImplementation.createNotificationChannel(channel);

      // Request notification permission
      final granted = await androidImplementation
          .requestNotificationsPermission();
      if (granted == false) {
        logger.w(
          '[AndroidNotificationService] Notification permission not granted',
        );
      }
    }

    _isInitialized = true;
  }

  /// Show persistent background notification using foreground service
  @override
  Future<void> showBackgroundNotification({required String roomName}) async {
    if (!_isInitialized) await init();

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

    final androidImpl = await _getAndroidImplementation();
    if (androidImpl != null) {
      // Make sure we have the necessary permissions to start the foreground service
      // Or fallback to regular notification to avoid SecurityException
      final permissionService = PermissionService();
      final hasCamera = await permissionService.hasCameraPermission();
      final hasMic = await permissionService.hasMicrophonePermission();
      final serviceTypes = <AndroidServiceForegroundType>{
        if (hasCamera) AndroidServiceForegroundType.foregroundServiceTypeCamera,
        if (hasMic)
          AndroidServiceForegroundType.foregroundServiceTypeMicrophone,
      };

      if (serviceTypes.isEmpty) {
        logger.w(
          '[AndroidNotificationService] No media permissions granted; '
          'falling back to regular notification instead of foreground service',
        );
        await _showRegularNotification(
          roomName: roomName,
          androidDetails: androidDetails,
        );
        return;
      }

      try {
        await androidImpl.startForegroundService(
          _backgroundNotificationId,
          _notificationTitle(roomName),
          _notificationBody,
          notificationDetails: androidDetails,
          payload: _notificationPayload,
          startType: AndroidServiceStartType
              .startNotSticky, // avoid potential NullPointerException crash
          foregroundServiceTypes: serviceTypes,
        );
      } catch (e) {
        logger.e('[AndroidNotificationService] Foreground service failed: $e');
        // Fallback to regular notification
        await _showRegularNotification(
          roomName: roomName,
          androidDetails: androidDetails,
        );
      }
    } else {
      // fallback: show regular notification
      logger.d(
        '[AndroidNotificationService] Using fallback regular notification',
      );
      await _showRegularNotification(
        roomName: roomName,
        androidDetails: androidDetails,
      );
    }
  }

  /// Hide foreground service notification
  @override
  Future<void> hideBackgroundNotification() async {
    final androidImpl = await _getAndroidImplementation();
    if (androidImpl != null) {
      await androidImpl.stopForegroundService();
    }

    try {
      await _notificationsPlugin.cancel(_backgroundNotificationId);
    } catch (e) {
      logger.w('[AndroidNotificationService] cancel notification failed: $e');
    }
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

  Future<void> _showRegularNotification({
    required String roomName,
    required AndroidNotificationDetails androidDetails,
  }) async {
    final details = NotificationDetails(android: androidDetails);
    await _notificationsPlugin.show(
      _backgroundNotificationId,
      _notificationTitle(roomName),
      _notificationBody,
      details,
      payload: _notificationPayload,
    );
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
