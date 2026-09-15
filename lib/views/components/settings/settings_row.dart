import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

/// Title emphasis inside a settings row.
///
/// [normal] is for rows the user reads first (actions, current values);
/// [muted] is for toggle labels, where the switch carries the state.
enum SettingsRowTone { normal, muted }

/// Base row for grouped settings lists.
///
/// Text stacks as [overline] / [title] / [subtitle]; [trailing] holds the
/// control (switch, chevron, thumbnail). The background fill and corner
/// rounding come from the enclosing group, so rows stay position-agnostic.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    required this.title,
    super.key,
    this.overline,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.tone = SettingsRowTone.normal,
  });

  /// Keeps single-line and two-line rows the same height within a group.
  static const double minHeight = 71;

  final String title;

  /// Small caption above [title], e.g. "Appearance" over "Dark".
  final String? overline;

  /// Explanatory caption below [title].
  final String? subtitle;

  final Widget? trailing;
  final VoidCallback? onTap;
  final SettingsRowTone tone;

  @override
  Widget build(BuildContext context) {
    final titleColor = tone == SettingsRowTone.normal
        ? context.colors.textNorm
        : context.colors.textWeak;

    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (overline != null) ...[
                  Text(
                    overline!,
                    style: ProtonStyles.captionMedium(
                      color: context.colors.textWeak,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(title, style: ProtonStyles.body2Medium(color: titleColor)),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: ProtonStyles.captionMedium(
                      color: context.colors.textHint,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: minHeight),
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}
