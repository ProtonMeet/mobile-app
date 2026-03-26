import 'package:flutter/widgets.dart';

class ControlAction {
  ControlAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.activeIcon,
    this.isActive = false,
    this.backgroundColor,
    this.inactiveBackgroundColor,
    this.badge,
    this.visiblePredicate,
    this.key,
  });

  final Widget icon;
  final Widget? activeIcon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isActive;
  final Color? backgroundColor;
  final Color? inactiveBackgroundColor;
  final String? badge;
  final bool Function()? visiblePredicate;
  final Key? key;
}
