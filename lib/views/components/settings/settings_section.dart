import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/settings/settings_group.dart';

/// Section title above a [SettingsGroup].
class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          Text(
            title,
            style: ProtonStyles.body2Semibold(color: context.colors.textWeak),
          ),
        ],
      ),
    );
  }
}

/// A titled block of settings rows.
///
/// Renders nothing when [rows] is empty, so callers can build rows with
/// collection-ifs for permissions and feature flags without also having to
/// hide the header.
class SettingsSection extends StatelessWidget {
  const SettingsSection({required this.title, required this.rows, super.key});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionHeader(title: title),
        SettingsGroup(children: rows),
      ],
    );
  }
}
