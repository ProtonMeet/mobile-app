import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/platform/html.window.dart';
import 'package:meet/views/components/local.toast.view.dart';
import 'package:meet/views/scenes/room/get_participant_display_colors.dart';
import 'package:meet/views/scenes/utils.dart';
import 'package:toastification/toastification.dart';

class _ToastificationRequest {
  _ToastificationRequest({
    required this.context,
    required this.title,
    required this.message,
    required this.onTap,
    required this.index,
    required this.autoCloseInSeconds,
    this.messageWidget,
    this.titleWidget,
    this.avatarName,
    this.bottomMargin = 80,
    this.horizontalMargin = 0,
  });

  final BuildContext context;
  final String title;
  final String message;
  final void Function(ToastificationItem)? onTap;
  final int index;
  final int autoCloseInSeconds;
  final Widget? messageWidget;
  final Widget? titleWidget;
  final String? avatarName;
  final double bottomMargin;
  final double horizontalMargin;
}

class _ToastificationContent extends ChangeNotifier {
  _ToastificationContent({
    required this.title,
    required this.message,
    required this.onTap,
    required this.index,
    this.messageWidget,
    this.titleWidget,
    this.avatarName,
  });

  static const int _contentExitMs = 150;
  static const int _contentEnterMs = 200;

  String title;
  String message;
  void Function(ToastificationItem)? onTap;
  int index;
  Widget? messageWidget;
  Widget? titleWidget;
  String? avatarName;
  double bottomMargin = 80;
  double horizontalMargin = 0;
  bool _disposed = false;
  double _contentOpacity = 1;
  int _contentGeneration = 0;

  double get contentOpacity => _contentOpacity;
  int get contentGeneration => _contentGeneration;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void apply(_ToastificationRequest request) {
    if (_disposed) return;
    title = request.title;
    message = request.message;
    onTap = request.onTap;
    index = request.index;
    messageWidget = request.messageWidget;
    titleWidget = request.titleWidget;
    avatarName = request.avatarName;
    bottomMargin = request.bottomMargin;
    horizontalMargin = request.horizontalMargin;
    _contentGeneration++;
    notifyListeners();
  }

  Future<void> transitionTo(_ToastificationRequest request) async {
    if (_disposed) return;
    _contentOpacity = 0;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: _contentExitMs));
    if (_disposed) return;
    apply(request);
    _contentOpacity = 0;
    notifyListeners();
    await Future<void>.delayed(Duration.zero);
    if (_disposed) return;
    _contentOpacity = 1;
    notifyListeners();
  }
}

class LocalToast {
  static final FToast fToast = FToast();
  static ToastificationItem? _activeToastificationItem;
  static _ToastificationContent? _activeToastificationContent;
  static Timer? _autoCloseTimer;
  static _ToastificationRequest? _pendingToastification;
  static bool _toastificationFlushScheduled = false;

  static void showErrorToast(BuildContext context, String message) {
    showToast(context, message, toastType: ToastType.error);
  }

  static void showWarningToast(BuildContext context, String message) {
    showToast(context, message, toastType: ToastType.warning);
  }

  static void showToast(
    BuildContext context,
    String message, {
    int duration = 2,
    ToastType toastType = ToastType.norm,
    Icon? icon,
    TextStyle? textStyle,
  }) {
    fToast.init(context);
    final toast = ToastView(
      toastType: toastType,
      icon: icon,
      message: message,
      textStyle: textStyle,
    );
    fToast.showToast(
      child: toast,
      gravity: ToastGravity.BOTTOM,
      toastDuration: Duration(seconds: duration),
    );
  }

  static void _clearActiveToastification({ToastificationItem? item}) {
    if (item != null && _activeToastificationItem?.id != item.id) return;

    _autoCloseTimer?.cancel();
    _autoCloseTimer = null;
    _activeToastificationContent?.dispose();
    _activeToastificationContent = null;
    _activeToastificationItem = null;
  }

  static void _scheduleAutoClose(int autoCloseInSeconds) {
    _autoCloseTimer?.cancel();
    final active = _activeToastificationItem;
    if (active == null) return;

    _autoCloseTimer = Timer(Duration(seconds: autoCloseInSeconds), () {
      if (_activeToastificationItem?.id != active.id) return;
      toastification.dismiss(active);
      _clearActiveToastification(item: active);
    });
  }

  /// Dismisses the currently visible toastification banner, if any.
  static void dismissActiveToastification() {
    final active = _activeToastificationItem;
    if (active == null) return;
    toastification.dismiss(active);
    _clearActiveToastification(item: active);
  }

  static void showToastification(
    BuildContext context,
    String title,
    String message, {
    void Function(ToastificationItem)? onTap,
    int index = 0,
    int autoCloseInSeconds = 2,
    Widget? messageWidget,
    Widget? titleWidget,
    String? avatarName,
    double bottomMargin = 80,
    double horizontalMargin = 0,
  }) {
    if (!isWindowsFocused()) {
      /// do not show toastification when page didn't have focus
      /// or it may not close automatically.
      return;
    }

    _pendingToastification = _ToastificationRequest(
      context: context,
      title: title,
      message: message,
      onTap: onTap,
      index: index,
      autoCloseInSeconds: autoCloseInSeconds,
      messageWidget: messageWidget,
      titleWidget: titleWidget,
      avatarName: avatarName,
      bottomMargin: bottomMargin,
      horizontalMargin: horizontalMargin,
    );
    if (_toastificationFlushScheduled) return;
    _toastificationFlushScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _toastificationFlushScheduled = false;
      final request = _pendingToastification;
      _pendingToastification = null;
      if (request == null || !request.context.mounted) return;

      if (_activeToastificationItem != null &&
          _activeToastificationContent != null) {
        _updateActiveToastification(request);
        return;
      }

      _presentToastification(request);
    });
  }

  static void _updateActiveToastification(_ToastificationRequest request) {
    unawaited(_updateActiveToastificationAsync(request));
  }

  static Future<void> _updateActiveToastificationAsync(
    _ToastificationRequest request,
  ) async {
    final content = _activeToastificationContent;
    if (content == null) return;
    await content.transitionTo(request);
    _scheduleAutoClose(request.autoCloseInSeconds);
  }

  static void _presentToastification(_ToastificationRequest request) {
    final content =
        _ToastificationContent(
            title: request.title,
            message: request.message,
            onTap: request.onTap,
            index: request.index,
            messageWidget: request.messageWidget,
            titleWidget: request.titleWidget,
            avatarName: request.avatarName,
          )
          ..bottomMargin = request.bottomMargin
          ..horizontalMargin = request.horizontalMargin;
    _activeToastificationContent = content;

    _activeToastificationItem = toastification.showCustom(
      context: request.context,
      alignment: Alignment.bottomCenter,
      callbacks: ToastificationCallbacks(
        onTap: (toastItem) => content.onTap?.call(toastItem),
        onDismissed: (item) => _clearActiveToastification(item: item),
      ),
      builder: (BuildContext context, ToastificationItem holder) {
        return ListenableBuilder(
          listenable: content,
          builder: (BuildContext context, Widget? child) {
            final colors = getParticipantDisplayColors(context, content.index);
            final avatarInitials = getInitials(
              content.avatarName ?? content.title,
            );
            final card = GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: content.onTap == null
                  ? null
                  : () => content.onTap!(holder),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: context.colors.backgroundNorm,
                  border: Border.all(color: context.colors.appBorderNorm),
                ),
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: colors.backgroundColor,
                      radius: 20,
                      child: Text(
                        avatarInitials,
                        style: ProtonStyles.body1Semibold(
                          color: colors.profileTextColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AnimatedOpacity(
                        opacity: content.contentOpacity,
                        duration: Duration(
                          milliseconds: content.contentOpacity >= 1
                              ? _ToastificationContent._contentEnterMs
                              : _ToastificationContent._contentExitMs,
                        ),
                        curve: Curves.easeOut,
                        child: Column(
                          key: ValueKey<int>(content.contentGeneration),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            content.titleWidget ??
                                Text(
                                  content.title,
                                  style: ProtonStyles.body1Semibold(
                                    color: context.colors.textNorm,
                                  ),
                                ),
                            if (content.message.isNotEmpty ||
                                content.messageWidget != null) ...[
                              const SizedBox(height: 4),
                              content.messageWidget ??
                                  Text(
                                    content.message,
                                    style: ProtonStyles.body2Regular(
                                      color: context.colors.textWeak,
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        toastification.dismiss(
                          holder,
                          showRemoveAnimation: false,
                        );
                        _clearActiveToastification(item: holder);
                      },
                      child: Icon(
                        Icons.close,
                        size: 20,
                        color: context.colors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
            );

            return Padding(
              padding: EdgeInsets.fromLTRB(
                content.horizontalMargin,
                0,
                content.horizontalMargin,
                content.bottomMargin,
              ),
              child: card,
            );
          },
        );
      },
    );

    _scheduleAutoClose(request.autoCloseInSeconds);
  }
}
