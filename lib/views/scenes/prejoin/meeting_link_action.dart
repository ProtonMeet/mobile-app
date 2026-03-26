import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';

/// Compact trailing actions with Paste + Copy icons.
///
/// Usage:
/// ```dart
/// MeetingLinkActions(
///   onPaste: () {
///     // open dialog, dispatch ImportMeeting, etc.
///   },
///   onCopy: () {
///     // copy to clipboard, show toast, etc.
///   },
/// )
/// ```
class MeetingLinkActions extends StatelessWidget {
  const MeetingLinkActions({
    required this.onImport,
    required this.onCopy,
    super.key,
    this.spacing = 8,
    this.radius = 20,
    this.iconSize = 20,
    this.iconColor,
    this.bgColor,
    this.hoverColor,
    this.padding = const EdgeInsets.only(right: 8),
    this.firstTooltip,
    this.secondTooltip,
    this.hideImport = false,
  });

  /// Tap handler for the copy icon.
  final VoidCallback onCopy;

  /// Tap handler for the import icon.
  final VoidCallback onImport;
  final bool hideImport;

  /// Space between icons.
  final double spacing;

  /// Circle avatar radius for each icon chip.
  final double radius;

  /// Icon size.
  final double iconSize;

  /// Optional override colors.
  final Color? iconColor;
  final Color? bgColor;
  final Color? hoverColor;

  /// Outer padding for the whole actions row.
  final EdgeInsetsGeometry padding;

  /// Optional tooltips.
  final String? firstTooltip;
  final String? secondTooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedIconColor = iconColor ?? theme.colorScheme.onSurface;
    final resolvedBgColor =
        bgColor ??
        theme.colorScheme.surface.withValues(alpha: 0.0); // transparent
    final resolvedHoverColor =
        hoverColor ?? theme.colorScheme.primary.withValues(alpha: 0.08);

    return Padding(
      padding: padding,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ActionIcon(
            // tooltip: firstTooltip ?? context.local.copy,
            icon: context.images.iconCopy.svg20(
              color: context.colors.interActionNorm,
            ),
            iconSize: iconSize,
            radius: radius,
            iconColor: resolvedIconColor,
            bgColor: resolvedBgColor,
            hoverColor: resolvedHoverColor,
            onTap: onCopy,
          ),
        ],
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.onTap,
    required this.iconColor,
    required this.bgColor,
    required this.hoverColor,
    required this.radius,
    required this.iconSize,
  });

  final Widget icon;
  final VoidCallback onTap;
  final Color iconColor;
  final Color bgColor;
  final Color hoverColor;
  final double radius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);

    final Widget content = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(color: bgColor, borderRadius: borderRadius),
      child: InkWell(
        borderRadius: borderRadius,
        onTap: onTap,
        hoverColor: hoverColor,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: CircleAvatar(
            backgroundColor: Colors.transparent,
            radius: radius,
            child: icon,
          ),
        ),
      ),
    );
    return Material(type: MaterialType.transparency, child: content);
  }
}
