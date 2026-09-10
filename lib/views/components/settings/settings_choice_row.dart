import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/settings/settings_row.dart';

/// Settings row for picking one option out of a short inline list.
class SettingsChoiceRow extends StatelessWidget {
  const SettingsChoiceRow({
    required this.title,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      title: title,
      onTap: onTap,
      trailing: Icon(
        selected ? Icons.check_circle : Icons.circle_outlined,
        color: selected
            ? context.colors.protonBlue
            : context.colors.interActionWeak,
        size: 22,
      ),
    );
  }
}
