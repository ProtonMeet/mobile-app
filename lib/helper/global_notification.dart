import 'dart:async';

import 'package:flutter/material.dart';

/// Immutable payload for a single global notification presentation.
@immutable
class GlobalNotificationData {
  const GlobalNotificationData({
    required this.content,
    this.backgroundColor,
    this.showCloseButton = true,
    this.onTap,
  });

  final String content;
  final Color? backgroundColor;
  final bool showCloseButton;
  final VoidCallback? onTap;

  @override
  bool operator ==(Object other) {
    return other is GlobalNotificationData &&
        other.content == content &&
        other.backgroundColor == backgroundColor &&
        other.showCloseButton == showCloseButton;
  }

  @override
  int get hashCode => Object.hash(content, backgroundColor, showCloseButton);
}

/// Controller that owns the currently visible global notification.
class GlobalNotificationController extends ChangeNotifier {
  GlobalNotificationController._();

  static final GlobalNotificationController instance =
      GlobalNotificationController._();

  GlobalNotificationData? _current;
  Timer? _autoDismissTimer;

  GlobalNotificationData? get current => _current;
  bool get isVisible => _current != null;

  void show({
    required String content,
    Color? backgroundColor,
    Duration duration = const Duration(seconds: 5),
    bool showCloseButton = true,
    VoidCallback? onTap,
  }) {
    _autoDismissTimer?.cancel();
    _current = GlobalNotificationData(
      content: content,
      backgroundColor: backgroundColor,
      showCloseButton: showCloseButton,
      onTap: onTap,
    );
    notifyListeners();

    if (duration > Duration.zero) {
      _autoDismissTimer = Timer(duration, dismiss);
    }
  }

  void dismiss() {
    if (_current == null) {
      return;
    }

    _autoDismissTimer?.cancel();
    _autoDismissTimer = null;
    _current = null;
    notifyListeners();
  }
}

/// Global top-of-screen notification API. Callable from anywhere without
/// [BuildContext].
class GlobalNotification {
  GlobalNotification._();

  static void show({
    required String content,
    Color? backgroundColor,
    Duration duration = const Duration(seconds: 5),
    bool showCloseButton = true,
    VoidCallback? onTap,
  }) {
    GlobalNotificationController.instance.show(
      content: content,
      backgroundColor: backgroundColor,
      duration: duration,
      showCloseButton: showCloseButton,
      onTap: onTap,
    );
  }

  static void dismiss() {
    GlobalNotificationController.instance.dismiss();
  }
}
