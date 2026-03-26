import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';

class HeaderTitle extends StatelessWidget {
  const HeaderTitle({
    required this.title,
    required this.subtitle,
    required this.isPersonalMeeting,
    this.recurrenceFrequency,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool isPersonalMeeting;
  final String? recurrenceFrequency;

  String? _getRecurrenceLabel(BuildContext context, String? frequency) {
    if (frequency == null) return null;
    switch (frequency.toUpperCase()) {
      case 'DAILY':
        return context.local.recurrence_daily;
      case 'WEEKLY':
        return context.local.recurrence_weekly;
      case 'MONTHLY':
        return context.local.recurrence_monthly;
      case 'YEARLY':
        return context.local.recurrence_yearly;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final recurrenceLabel = _getRecurrenceLabel(context, recurrenceFrequency);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: ProtonStyles.headline(color: context.colors.textNorm),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: isPersonalMeeting
                ? ProtonStyles.body2Semibold(color: context.colors.protonBlue)
                : ProtonStyles.body2Medium(color: context.colors.textWeak),
          ),
          if (recurrenceLabel != null) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                context.images.iconMeetingRecurring.svg16(
                  color: context.colors.textWeak,
                ),
                const SizedBox(width: 6),
                Text(
                  recurrenceLabel,
                  textAlign: TextAlign.center,
                  style: ProtonStyles.body2Medium(
                    color: context.colors.textWeak,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
