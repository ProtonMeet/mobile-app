import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/views/components/alerts/base_bottom_sheet.dart';
import 'package:meet/views/components/bottom.sheets/bottom_sheet_handle_bar.dart';

typedef OnInvalidSelection = void Function(String message);

Future<void> showWaitingRoomSheet(
  BuildContext context, {
  required bool selected,
  required bool isPaidUser,
  required ValueChanged<bool> onSelect,
  OnInvalidSelection? onInvalidSelection,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.transparent,
    builder: (context) => BaseBottomSheet(
      backgroundColor: context.colors.backgroundNorm,
      contentPadding: const EdgeInsets.only(bottom: 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BottomSheetHandleBar(),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Align(
                child: Text(
                  context.local.schedule_waiting_room,
                  style: ProtonStyles.body2Medium(
                    color: context.colors.textHint,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            _WaitingRoomOptions(
              selected: selected,
              isPaidUser: isPaidUser,
              onSelect: onSelect,
              onInvalidSelection: onInvalidSelection,
            ),
          ],
        ),
      ),
    ),
  );
}

class _WaitingRoomOptions extends StatelessWidget {
  const _WaitingRoomOptions({
    required this.selected,
    required this.isPaidUser,
    required this.onSelect,
    this.onInvalidSelection,
  });

  final bool selected;
  final bool isPaidUser;
  final ValueChanged<bool> onSelect;
  final OnInvalidSelection? onInvalidSelection;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WaitingRoomOption(
            title: context.local.switch_on,
            hint: context.local.schedule_waiting_room_on_hint,
            isSelected: selected,
            enabled: isPaidUser,
            onTap: () {
              if (!isPaidUser) {
                onInvalidSelection?.call(
                  context.local.waiting_room_paid_feature,
                );
                return;
              }
              onSelect(true);
              Navigator.pop(context);
            },
          ),
          _WaitingRoomOption(
            title: context.local.switch_off,
            hint: context.local.schedule_waiting_room_off_hint,
            isSelected: !selected,
            enabled: true,
            onTap: () {
              onSelect(false);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}

class _WaitingRoomOption extends StatelessWidget {
  const _WaitingRoomOption({
    required this.title,
    required this.hint,
    required this.isSelected,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final String hint;
  final bool isSelected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final titleColor = enabled
        ? context.colors.interActionNorm
        : context.colors.textDisable;
    final hintColor = enabled
        ? context.colors.textWeak
        : context.colors.textDisable;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: InkWell(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: ProtonStyles.body1Semibold(color: titleColor),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hint,
                    style: ProtonStyles.body2Regular(color: hintColor),
                  ),
                ],
              ),
            ),
            if (isSelected)
              context.images.iconCheckmark.svg24(color: titleColor),
          ],
        ),
      ),
    );
  }
}
