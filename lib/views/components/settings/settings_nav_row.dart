import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/settings/settings_row.dart';

/// Settings row that opens another surface (sheet, picker, external link).
///
/// Use [overline] for "label above current value" rows and [value] for rows
/// that show the current selection inline next to the chevron.
class SettingsNavRow extends StatelessWidget {
  const SettingsNavRow({
    required this.title,
    required this.onTap,
    super.key,
    this.overline,
    this.subtitle,
    this.value,
    this.accessory,
    this.chevron = Icons.chevron_right,
  });

  final String title;
  final VoidCallback onTap;
  final String? overline;
  final String? subtitle;

  /// Current selection rendered next to the chevron.
  final String? value;

  /// Extra preview widget between [value] and the chevron, e.g. a thumbnail.
  final Widget? accessory;

  final IconData chevron;

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      title: title,
      overline: overline,
      subtitle: subtitle,
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            Text(
              value!,
              style: ProtonStyles.body2Regular(color: context.colors.textWeak),
            ),
          ?accessory,
          const SizedBox(width: 4),
          Icon(chevron, color: context.colors.textWeak, size: 22),
        ],
      ),
    );
  }
}
