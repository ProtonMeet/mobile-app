import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/views/components/alerts/base_bottom_sheet.dart';
import 'package:meet/views/components/bottom.sheets/bottom_sheet_handle_bar.dart';

Future<void> showDurationSheet(
  BuildContext context, {
  required List<int> options,
  required int selectedMinutes,
  required String Function(int minutes) formatDuration,
  required ValueChanged<int> onSelect,
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
                _DurationWidget(
                  options: options,
                  selectedMinutes: selectedMinutes,
                  formatDuration: formatDuration,
                  onSelect: onSelect,
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _DurationWidget extends StatelessWidget {
  const _DurationWidget({
    required this.options,
    required this.selectedMinutes,
    required this.formatDuration,
    required this.onSelect,
  });

  final List<int> options;
  final int selectedMinutes;
  final String Function(int minutes) formatDuration;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: options.map((minutes) {
          final isSelected = selectedMinutes == minutes;
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: InkWell(
              onTap: () {
                onSelect(minutes);
                Navigator.pop(context);
              },
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      formatDuration(minutes),
                      style: ProtonStyles.body1Medium(
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
