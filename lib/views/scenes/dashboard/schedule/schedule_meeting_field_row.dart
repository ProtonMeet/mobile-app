import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

class ScheduleMeetingFieldRow extends StatelessWidget {
  const ScheduleMeetingFieldRow({
    required this.label,
    required this.onTap,
    this.trailing,
    this.child,
    this.icon,
    this.topBorder = true,
    this.bottomBorder = true,
    this.validationError,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final Widget? trailing;
  final Widget? child;
  final Widget? icon;
  final bool topBorder;
  final bool bottomBorder;
  final String? validationError;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: BoxDecoration(
          border: Border(
            top: topBorder
                ? BorderSide(color: Colors.white.withValues(alpha: 0.04))
                : BorderSide.none,
            bottom: bottomBorder
                ? BorderSide(color: Colors.white.withValues(alpha: 0.04))
                : BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            if (icon != null) ...[icon!, const SizedBox(width: 16)],
            Expanded(
              child:
                  child ??
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: ProtonStyles.body2Medium(
                          color: context.colors.textNorm,
                        ),
                      ),

                      if (validationError != null) ...[
                        Text(
                          validationError!,
                          style: ProtonStyles.body2Medium(
                            color: context.colors.notificationError,
                          ),
                        ),
                      ],
                    ],
                  ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    );
  }
}
