import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

enum ToastType { success, warning, error, norm, normlight }

extension ToastTypeExtension on ToastType {
  Color getColor(BuildContext context) {
    switch (this) {
      case ToastType.success:
        return context.colors.notificationNorm;
      case ToastType.warning:
        return context.colors.signalWaning;
      case ToastType.error:
        return context.colors.notificationError;
      case ToastType.norm:
        return context.colors.notificationNorm;
      case ToastType.normlight:
        return context.colors.textNorm;
    }
  }
}

class ToastView extends StatelessWidget {
  const ToastView({
    required this.toastType,
    required this.message,
    this.icon,
    this.textStyle,
    super.key,
  });

  final ToastType toastType;
  final Icon? icon;
  final String message;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final toast = Container(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.0),
        color: toastType.getColor(context),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[icon!, const SizedBox(width: 12.0)],
          Flexible(
            child: Text(
              message,
              style:
                  textStyle ??
                  ProtonStyles.body2Medium(color: context.colors.textInverted),
            ),
          ),
        ],
      ),
    );
    return toast;
  }
}
