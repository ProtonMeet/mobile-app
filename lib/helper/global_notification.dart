import 'dart:async';

import 'package:flutter/material.dart';

/// Immutable payload for a single global notification presentation.
@immutable
class GlobalNotificationData {
  const GlobalNotificationData({
    this.content,
    this.contentWidget,
    this.backgroundColor,
    this.showCloseButton = true,
    this.onTap,
  }) : assert(
         content != null || contentWidget != null,
         'Either content or contentWidget must be provided',
       );

  final String? content;
  final Widget? contentWidget;
  final Color? backgroundColor;
  final bool showCloseButton;
  final VoidCallback? onTap;

  @override
  bool operator ==(Object other) {
    return other is GlobalNotificationData &&
        other.content == content &&
        other.contentWidget == contentWidget &&
        other.backgroundColor == backgroundColor &&
        other.showCloseButton == showCloseButton;
  }

  @override
  int get hashCode =>
      Object.hash(content, contentWidget, backgroundColor, showCloseButton);
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
    String? content,
    Widget? contentWidget,
    Color? backgroundColor,
    Duration duration = const Duration(seconds: 5),
    bool showCloseButton = true,
    VoidCallback? onTap,
  }) {
    _autoDismissTimer?.cancel();
    _current = GlobalNotificationData(
      content: content,
      contentWidget: contentWidget,
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
    String? content,
    Widget? contentWidget,
    Color? backgroundColor,
    Duration duration = const Duration(seconds: 5),
    bool showCloseButton = true,
    VoidCallback? onTap,
  }) {
    GlobalNotificationController.instance.show(
      content: content,
      contentWidget: contentWidget,
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
