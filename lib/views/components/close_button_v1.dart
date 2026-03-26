import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

class CloseButtonV1 extends StatelessWidget {
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final Color? iconColor;
  final double? iconSize;

  const CloseButtonV1({
    super.key,
    this.onPressed,
    this.backgroundColor,
    this.iconColor,
    this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = backgroundColor ?? context.colors.interActionNormMinor3;

    if (bgColor == Colors.transparent) {
      return IconButton(
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
      );
    }

    return CircleAvatar(
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
    );
  }
}
