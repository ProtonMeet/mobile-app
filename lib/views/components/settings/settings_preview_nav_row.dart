import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/local_toast.dart';
import 'package:meet/views/components/settings/settings_nav_row.dart';

/// Nav row for settings that are visible in preview but not implemented yet.
class SettingsPreviewNavRow extends StatelessWidget {
  const SettingsPreviewNavRow({required this.title, super.key, this.overline});

  final String title;
  final String? overline;

  @override
  Widget build(BuildContext context) {
    return SettingsNavRow(
      title: title,
      overline: overline,
      onTap: () =>
          LocalToast.showToast(context, context.local.feature_not_ready),
    );
  }
}
