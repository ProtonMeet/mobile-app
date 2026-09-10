import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/local_toast.dart';
import 'package:meet/views/components/settings/settings_row.dart';

/// Settings row with a switch.
///
/// A null [onChanged] means the row is visible but not actionable (missing
/// permission, or a feature that is still rolling out); tapping it explains
/// that instead of silently doing nothing.
class SettingsToggleRow extends StatelessWidget {
  const SettingsToggleRow({
    required this.title,
    required this.value,
    super.key,
    this.overline,
    this.subtitle,
    this.onChanged,
    this.isLoading = false,
    this.silentWhenDisabled = false,
    this.tone = SettingsRowTone.muted,
  });

  final String title;

  /// Small caption above [title], for rows that read as "label / current value".
  final String? overline;

  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool isLoading;

  /// When true with a null [onChanged], the switch is disabled without tap feedback.
  final bool silentWhenDisabled;
  final SettingsRowTone tone;

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      title: title,
      overline: overline,
      subtitle: subtitle,
      tone: tone,
      trailing: isLoading
          ? SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  context.colors.protonBlue,
                ),
              ),
            )
          : Container(
              height: 33,
              width: 56,
              decoration: BoxDecoration(
                border: Border.all(color: context.colors.interActionWeak),
                borderRadius: BorderRadius.circular(40),
              ),
              child: CupertinoSwitch(
                value: value,
                onChanged: onChanged ??
                    (silentWhenDisabled
                        ? null
                        : (_) => LocalToast.showToast(
                            context,
                            context.local.feature_not_ready,
                          )),
                activeTrackColor: context.colors.backgroundNorm,
                inactiveTrackColor: context.colors.backgroundNorm,
                inactiveThumbColor: context.colors.interActionWeak,
                thumbColor: context.colors.protonBlue,
              ),
            ),
    );
  }
}
