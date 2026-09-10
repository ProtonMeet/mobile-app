import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/settings/settings_group.dart';
import 'package:meet/views/components/settings/settings_row.dart';

/// Standalone tappable settings row that carries its own fill and corners.
///
/// Prefer [SettingsSection] / [SettingsGroup] for new lists — they position
/// rows automatically. This variant exists for ad-hoc lists (debug menus)
/// that place rows individually and set [isFirst] / [isLast] themselves.
class SettingsActionItem extends StatelessWidget {
  const SettingsActionItem({
    required this.title,
    required this.onTap,
    super.key,
    this.isFirst = false,
    this.isLast = false,
    this.isDanger = false,
    this.suffix,
  });

  final String title;
  final VoidCallback onTap;
  final bool isFirst;
  final bool isLast;
  final bool isDanger;
  final Widget? suffix;

  BorderRadius get _borderRadius {
    const radius = Radius.circular(SettingsGroup.cornerRadius);
    return BorderRadius.only(
      topLeft: isFirst ? radius : Radius.zero,
      topRight: isFirst ? radius : Radius.zero,
      bottomLeft: isLast ? radius : Radius.zero,
      bottomRight: isLast ? radius : Radius.zero,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: SettingsGroup.surfaceColor,
        borderRadius: _borderRadius,
        clipBehavior: Clip.antiAlias,
        child: SettingsRow(
          title: title,
          onTap: onTap,
          trailing: isDanger
              ? Container(
                  width: 40,
                  height: 40,
                  padding: const EdgeInsets.all(12),
                  decoration: ShapeDecoration(
                    color: const Color(0xFF3D2A3D),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                  child: Icon(
                    Icons.delete_outline,
                    color: context.colors.notificationError,
                    size: 16,
                  ),
                )
              : suffix,
        ),
      ),
    );
  }
}
