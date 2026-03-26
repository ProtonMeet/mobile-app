import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/views/components/alerts/base_bottom_sheet.dart';
import 'package:meet/views/components/bottom.sheets/bottom_sheet_handle_bar.dart';

import 'schedule_meeting_dialog.dart';

Future<void> showRecurrenceSheet(
  BuildContext context, {
  required RecurrenceFrequency selected,
  required ValueChanged<RecurrenceFrequency> onSelect,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.transparent,
    builder: (context) => LayoutBuilder(
      builder: (context, constraints) {
        return BaseBottomSheet(
          backgroundColor: context.colors.backgroundNorm,
          contentPadding: const EdgeInsets.only(bottom: 24),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BottomSheetHandleBar(),
                const SizedBox(height: 8),
                _RecurrenceWidget(selected: selected, onSelect: onSelect),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _RecurrenceWidget extends StatelessWidget {
  const _RecurrenceWidget({required this.selected, required this.onSelect});

  final RecurrenceFrequency selected;
  final ValueChanged<RecurrenceFrequency> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: RecurrenceFrequency.values.map((freq) {
          final isSelected = selected == freq;
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: InkWell(
              onTap: () {
                onSelect(freq);
                Navigator.pop(context);
              },
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      freq.label,
                      style: ProtonStyles.body1Semibold(
                        color: context.colors.interActionNorm,
                      ),
                    ),
                  ),
                  if (isSelected)
                    context.images.iconCheckmark.svg24(
                      color: context.colors.interActionNorm,
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
