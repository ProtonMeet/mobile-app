import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/alerts/base_bottom_sheet.dart';
import 'package:meet/views/components/bottom.sheets/bottom_sheet_handle_bar.dart';
import 'package:meet/views/scenes/room/controls_bar/controls_action.dart';

class OverflowMenuBottomSheet extends StatelessWidget {
  const OverflowMenuBottomSheet({required this.actions, super.key});

  final List<ControlAction> actions;

  static void show(BuildContext context, List<ControlAction> actions) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.transparent,
      builder: (context) => OverflowMenuBottomSheet(actions: actions),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = context.height * 0.9;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: BaseBottomSheet(
        maxHeight: maxHeight,
        blurSigma: 10,
        backgroundColor: context.colors.backgroundDark.withValues(alpha: 0.60),
        borderRadius: BorderRadius.circular(40),
        borderSide: BorderSide(color: context.colors.borderCard),
        contentPadding: const EdgeInsets.only(bottom: 12),
        child: SafeArea(
          left: false,
          right: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              const BottomSheetHandleBar(),
              const SizedBox(height: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < actions.length; i++) ...[
                    _MenuItem(action: actions[i]),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.action});

  final ControlAction action;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              Navigator.of(context).pop();
              action.onPressed();
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: 24),
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: ColorFiltered(
                      colorFilter: ColorFilter.mode(
                        context.colors.interActionNorm,
                        BlendMode.srcIn,
                      ),
                      child: action.isActive
                          ? action.activeIcon ?? action.icon
                          : action.icon,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      action.tooltip,
                      style: ProtonStyles.body1Medium(
                        color: context.colors.interActionNorm,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
