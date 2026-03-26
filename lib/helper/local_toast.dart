import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/platform/html.window.dart';
import 'package:meet/views/components/local.toast.view.dart';
import 'package:meet/views/scenes/room/get_participant_display_colors.dart';
import 'package:toastification/toastification.dart';

class LocalToast {
  static final FToast fToast = FToast();

  static void showErrorToast(BuildContext context, String message) {
    showToast(context, message, toastType: ToastType.error);
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

  static void showToastification(
    BuildContext context,
    String title,
    String message, {
    void Function(ToastificationItem)? onTap,
    int index = 0,
    int autoCloseInSeconds = 2,
  }) {
    if (!isWindowsFocused()) {
      /// do not show toastification when page didn't have focus
      /// or it may not close automatically.
      return;
    }

    // Dismiss all existing toasts to ensure only one is displayed at a time
    toastification.dismissAll();

    final colors = getParticipantDisplayColors(context, index);
    toastification.showCustom(
      context: context,
      autoCloseDuration: Duration(seconds: autoCloseInSeconds),
      alignment: Alignment.bottomCenter,
      callbacks: ToastificationCallbacks(
        onTap: (toastItem) => onTap?.call(toastItem),
      ),
      builder: (BuildContext context, ToastificationItem holder) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: context.colors.backgroundNorm,
            border: Border.all(color: context.colors.appBorderNorm),
          ),
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.only(bottom: 80),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: colors.backgroundColor,
                radius: 20,
                child: Text(
                  title.isNotEmpty ? title[0].toUpperCase() : "",
                  style: ProtonStyles.body1Semibold(
                    color: colors.profileTextColor,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: ProtonStyles.body1Semibold(
                        color: context.colors.textNorm,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message,
                      style: ProtonStyles.body2Regular(
                        color: context.colors.textWeak,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => toastification.dismiss(holder),
                child: Icon(
                  Icons.close,
                  size: 20,
                  color: context.colors.textHint,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
