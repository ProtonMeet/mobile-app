import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/test_id.dart';

class CloseButtonV1 extends StatelessWidget {
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final Color? iconColor;
  final double? iconSize;
  final String? testId;

  const CloseButtonV1({
    super.key,
    this.onPressed,
    this.backgroundColor,
    this.iconColor,
    this.iconSize,
    this.testId,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = backgroundColor ?? context.colors.interActionNormMinor3;

    if (bgColor == Colors.transparent) {
      return withTestId(
        testId,
        IconButton(
          icon: context.images.iconClose.svg(
            width: iconSize ?? 20,
            height: iconSize ?? 20,
            fit: BoxFit.fill,
            colorFilter: ColorFilter.mode(
              iconColor ?? context.colors.interActionNorm,
              BlendMode.srcIn,
            ),
          ),
          onPressed: onPressed,
        ),
        button: true,
      );
    }

    return withTestId(
      testId,
      CircleAvatar(
        radius: 20,
        backgroundColor: bgColor,
        child: IconButton(
          icon: context.images.iconClose.svg(
            width: iconSize ?? 20,
            height: iconSize ?? 20,
            fit: BoxFit.fill,
            colorFilter: ColorFilter.mode(
              iconColor ?? context.colors.interActionNorm,
              BlendMode.srcIn,
            ),
          ),
          onPressed: onPressed,
        ),
      ),
      button: true,
    );
  }
}
