import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/custom.tooltip.dart';

class ControlIconButton extends StatelessWidget {
  final Widget icon;
  final Widget? activeIcon;
  final VoidCallback onPressed;
  final bool isActive;
  final String? badge;
  final double size;
  final Color? backgroundColor;
  final Color? inactiveBackgroundColor;
  final Color? activeColor;
  final Color? inactiveColor;
  final String? tooltip;

  const ControlIconButton({
    required this.icon,
    required this.onPressed,
    super.key,
    this.activeIcon,
    this.isActive = false,
    this.badge,
    this.size = 56,
    this.backgroundColor,
    this.inactiveBackgroundColor,
    this.activeColor,
    this.inactiveColor,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: ShapeDecoration(
        color: isActive
            ? backgroundColor ?? context.colors.controlButtonBackground
            : inactiveBackgroundColor ??
                  backgroundColor ??
                  context.colors.controlButtonBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9000),
        ),
      ),
      child: Stack(
        children: [
          Center(
            child: CustomTooltip(
              message: tooltip ?? "",
              child: IconButton(
                icon: isActive ? (activeIcon ?? icon) : icon,
                color: isActive
                    ? (activeColor ?? context.colors.textInverted)
                    : (inactiveColor ?? context.colors.white),
                onPressed: onPressed,
              ),
            ),
          ),
          if (badge != null)
            Positioned(
              left: 38,
              top: 0,
              child: Container(
                width: 18,
                height: 18,
                // padding: const EdgeInsets.all(8),
                decoration: ShapeDecoration(
                  color: const Color(0xFF5E5F66),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(200000),
                  ),
                ),
                child: Text(
                  badge!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
