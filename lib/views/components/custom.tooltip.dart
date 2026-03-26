import 'package:flutter/material.dart';
import 'package:just_the_tooltip/just_the_tooltip.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

class CustomTooltip extends StatelessWidget {
  final String message;
  final Widget child;
  final AxisDirection? preferredDirection;

  const CustomTooltip({
    required this.message,
    required this.child,
    this.preferredDirection = AxisDirection.up,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return JustTheTooltip(
      tailLength: 12,
      tailBaseWidth: 16,
      margin: const EdgeInsets.symmetric(horizontal: defaultPadding * 2),
      preferredDirection: preferredDirection!,
      backgroundColor: context.colors.black,
      triggerMode: TooltipTriggerMode.tap,
      content: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(
          message,
          style: ProtonStyles.body2Regular(color: context.colors.textInverted),
          textAlign: TextAlign.center,
        ),
      ),
      child: child,
    );
  }
}
