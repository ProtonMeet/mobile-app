import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/views/components/alerts/base_bottom_sheet.dart';
import 'package:meet/views/components/bottom.sheets/bottom_sheet_handle_bar.dart';
import 'package:meet/views/scenes/dashboard/upcoming/upcoming_menu_item.dart';

Future<void> showAddToCalendarSheet(
  BuildContext context, {
  required VoidCallback onAdd,
  required VoidCallback onShare,
  required VoidCallback onOpenOutlook,
  required VoidCallback onOpenGoogle,
  required VoidCallback onOpenProton,
  bool showOutlookCalendar = false,
  bool showProtonCalendar = false,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.transparent,
    builder: (context) => LayoutBuilder(
      builder: (context, constraints) {
        final screenHeight = context.height;
        final availableHeight = screenHeight * 0.9;

        // Calculate content height based on number of items
        int itemCount = 3; // System calendar, Google calendar, Share ICS
        if (showOutlookCalendar) itemCount++;
        if (showProtonCalendar) itemCount++;

        final contentHeight = (itemCount * 60.0) + 100.0; // Items + padding
        final maxHeight = contentHeight > availableHeight
            ? availableHeight
            : contentHeight;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: BaseBottomSheet(
            blurSigma: 10,
            maxHeight: maxHeight,
            backgroundColor: context.colors.backgroundDark.withValues(
              alpha: 0.80,
            ),
            contentPadding: const EdgeInsets.only(bottom: 24),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  const BottomSheetHandleBar(),
                  const SizedBox(height: 8),
                  _AddToCalendarWidget(
                    onAdd: onAdd,
                    onShare: onShare,
                    onOpenOutlook: onOpenOutlook,
                    onOpenGoogle: onOpenGoogle,
                    onOpenProton: onOpenProton,
                    showOutlookCalendar: showOutlookCalendar,
                    showProtonCalendar: showProtonCalendar,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _AddToCalendarWidget extends StatelessWidget {
  const _AddToCalendarWidget({
    required this.onAdd,
    required this.onShare,
    required this.onOpenOutlook,
    required this.onOpenGoogle,
    required this.onOpenProton,
    required this.showOutlookCalendar,
    required this.showProtonCalendar,
  });

  final VoidCallback onAdd;
  final VoidCallback onShare;
  final VoidCallback onOpenOutlook;
  final VoidCallback onOpenGoogle;
  final VoidCallback onOpenProton;
  final bool showOutlookCalendar;
  final bool showProtonCalendar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          UpcomingMenuItem(
            icon: context.images.iconAddToCalendar.svg20(
              color: context.colors.interActionNorm,
            ),
            label: context.local.calendar_system,
            labelColor: context.colors.interActionNorm,
            onTap: () {
              Navigator.of(context).pop();
              onAdd();
            },
          ),
          const SizedBox(height: 16),
          const SizedBox(height: 16),
          UpcomingMenuItem(
            icon: context.images.iconAddToCalendar.svg20(
              color: context.colors.interActionNorm,
            ),
            label: context.local.calendar_google,
            labelColor: context.colors.interActionNorm,
            onTap: () {
              Navigator.of(context).pop();
              onOpenGoogle();
            },
          ),
          const SizedBox(height: 16),
          const SizedBox(height: 16),
          UpcomingMenuItem(
            icon: context.images.iconUploadFile.svg20(
              color: context.colors.interActionNorm,
            ),
            label: context.local.calendar_share_ics,
            labelColor: context.colors.interActionNorm,
            onTap: () {
              Navigator.of(context).pop();
              onShare();
            },
          ),
          const SizedBox(height: 16),
          if (showOutlookCalendar) ...[
            const SizedBox(height: 16),
            UpcomingMenuItem(
              icon: context.images.iconAddToCalendar.svg20(
                color: context.colors.interActionNorm,
              ),
              label: context.local.calendar_outlook,
              labelColor: context.colors.interActionNorm,
              onTap: () {
                Navigator.of(context).pop();
                onOpenOutlook();
              },
            ),
            const SizedBox(height: 16),
          ],
          if (showProtonCalendar) ...[
            const SizedBox(height: 16),
            UpcomingMenuItem(
              icon: context.images.iconAddToCalendar.svg20(
                color: context.colors.interActionNorm,
              ),
              label: context.local.calendar_proton,
              labelColor: context.colors.interActionNorm,
              onTap: () {
                Navigator.of(context).pop();
                onOpenProton();
              },
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}
