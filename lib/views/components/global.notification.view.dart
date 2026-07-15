import 'package:flutter/material.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/global_notification.dart';

class GlobalNotificationView extends StatelessWidget {
  const GlobalNotificationView({
    required this.data,
    required this.onDismiss,
    super.key,
  });

  final GlobalNotificationData data;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.viewPaddingOf(context).top;
    final backgroundColor =
        data.backgroundColor ?? context.colors.notificationNorm;

    return Material(
      color: backgroundColor,
      elevation: 4,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          defaultPadding,
          topInset + 12,
          defaultPadding,
          12,
        ),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: data.onTap,
                child: Center(
                  child: Text(
                    data.content,
                    style: ProtonStyles.body2Medium(
                      color: context.colors.textInverted,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            if (data.showCloseButton) ...[
              const SizedBox(width: 8),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: context.images.iconClose.svg(
                  width: 20,
                  height: 20,
                  fit: BoxFit.fill,
                  colorFilter: ColorFilter.mode(
                    context.colors.textInverted,
                    BlendMode.srcIn,
                  ),
                ),
                onPressed: onDismiss,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
