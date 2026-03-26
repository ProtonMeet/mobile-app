import 'package:meet/managers/manager.dart';

/// Interface for notification service
/// Different platforms (Android, iOS, Desktop) will implement this interface
/// Currently only Android implementation exists
abstract class NotificationService implements Manager {
  // ============================================================================
  // Background Notification Methods
  // ============================================================================

  /// Show persistent background notification (ongoing, non-dismissible)
  /// This notification is shown when the app goes to background
  Future<void> showBackgroundNotification({required String roomName});

  /// Hide background notification
  Future<void> hideBackgroundNotification();

  /// Set background notification tap callback
  void setBackgroundNotificationTapCallback(Future<void> Function()? callback);

  /// Clear background notification tap callback
  void clearBackgroundNotificationTapCallback();

  // ============================================================================
  // Future notification types can be added here
  // For example:
  // - showIncomingCallNotification()
  // - showMessageNotification()
  // - showReminderNotification()
  // ============================================================================
}
