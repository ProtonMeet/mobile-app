import 'dart:async';
import 'package:flutter/services.dart';
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

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  Future<void> Function()? _onNotificationTapCallback;

  // Debounce timer: prevents ForegroundServiceDidNotStartInTimeException caused
  // by rapid inactive→resumed transitions (e.g. notification shade, system dialog)
  // that start the service and then immediately stop it before startForeground() runs.
  Timer? _pendingStartTimer;
  bool _stopRequested = false;

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

  /// Show persistent background notification using foreground service.
  ///
  /// Start is debounced by 300 ms so brief inactive→resumed transitions
  /// (notification shade, system dialogs) never trigger a service start that
  /// would be stopped before [startForeground()] runs — which would cause
  /// [ForegroundServiceDidNotStartInTimeException].
  @override
  Future<void> showBackgroundNotification({required String roomName}) async {
    if (!_isInitialized) await init();

    // Cancel any previously scheduled start and arm a new one.
    _pendingStartTimer?.cancel();
    _stopRequested = false;

    _pendingStartTimer = Timer(const Duration(milliseconds: 300), () {
      _pendingStartTimer = null;
      if (!_stopRequested) {
        _doStartForegroundService(roomName);
      }
    });
  }

  Future<void> _doStartForegroundService(String roomName) async {
    // Build the set of foreground service types based on permissions that are
    // actually granted right now. Android 14+ calls validateForegroundServiceType()
    // inside Service.startForeground() and throws SecurityException — from within
    // the service's onStartCommand(), not catchable via the Dart method channel —
    // if you request a type whose runtime permission is not currently held.
    final permissionService = PermissionService();
    final hasMic = await permissionService.hasMicrophonePermission();
    final hasCam = await permissionService.hasCameraPermission();

    final Set<AndroidServiceForegroundType> serviceTypes = {
      if (hasMic) AndroidServiceForegroundType.foregroundServiceTypeMicrophone,
      if (hasCam) AndroidServiceForegroundType.foregroundServiceTypeCamera,
    };

    if (serviceTypes.isEmpty) {
      logger.w(
        '[AndroidNotificationService] No authorized foreground service types '
        '(mic=$hasMic cam=$hasCam) — falling back to plain notification',
      );
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

    final title = roomName.isNotEmpty ? 'In Meeting: $roomName' : 'In Meeting';
    const body = 'Tap to return to meeting';

    final androidImpl = await _getAndroidImplementation();
    if (androidImpl != null && serviceTypes.isNotEmpty) {
      try {
        await androidImpl.startForegroundService(
          _backgroundNotificationId,
          title,
          body,
          notificationDetails: androidDetails,
          payload: 'meeting_foreground',
          startType: AndroidServiceStartType
              .startNotSticky, // avoid potential NullPointerException crash
          foregroundServiceTypes: serviceTypes,
        );
        return;
      } catch (e) {
        logger.e('[AndroidNotificationService] Foreground service failed: $e');
        // Fall through to plain notification
      }
    }

    // Fallback: plain (non-foreground) notification — no service type validation.
    final details = NotificationDetails(android: androidDetails);
    try {
      await _notificationsPlugin.show(
        _backgroundNotificationId,
        title,
        body,
        details,
        payload: 'meeting_foreground',
      );
    } catch (e) {
      logger.e('[AndroidNotificationService] Plain notification failed: $e');
    }
  }

  /// Hide foreground service notification
  @override
  Future<void> hideBackgroundNotification() async {
    // Cancel any pending debounced start — service won't start at all.
    _pendingStartTimer?.cancel();
    _pendingStartTimer = null;
    _stopRequested = true;

    final androidImpl = await _getAndroidImplementation();
    if (androidImpl != null) {
      try {
        await androidImpl.stopForegroundService();
      } on PlatformException catch (e) {
        // Service may already be stopped or the method channel may be partially
        // torn down — log a warning rather than crashing.
        logger.w(
          '[AndroidNotificationService] stopForegroundService failed '
          '(may already be stopped): $e',
        );
      }
    }

    try {
      await _notificationsPlugin.cancel(_backgroundNotificationId);
    } on PlatformException catch (e) {
      logger.w(
        '[AndroidNotificationService] cancel notification failed: $e',
      );
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
    if (response.payload == 'meeting_foreground') {
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
    _pendingStartTimer?.cancel();
    _pendingStartTimer = null;
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
