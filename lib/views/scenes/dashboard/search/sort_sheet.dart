import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/helper/local_toast.dart';
import 'package:meet/views/components/alerts/base_bottom_sheet.dart';
import 'package:meet/views/components/bottom.sheets/bottom_sheet_handle_bar.dart';
import 'package:meet/views/components/local.toast.view.dart';
import 'package:meet/views/scenes/dashboard/upcoming/meet_upcoming_title.dart';

enum SortOptionMyRooms { newCreated, lastUsed }

enum SortOptionMyMeetings { upcoming, past, newCreated }

extension SortOptionMyRoomsExtension on SortOptionMyRooms {
  String getLabel(BuildContext context) {
    switch (this) {
      case SortOptionMyRooms.newCreated:
        return context.local.sort_new_created;
      case SortOptionMyRooms.lastUsed:
        return context.local.sort_last_used;
    }
  }
}

extension SortOptionMyMeetingsExtension on SortOptionMyMeetings {
  String getLabel(BuildContext context) {
    switch (this) {
      case SortOptionMyMeetings.upcoming:
        return context.local.sort_upcoming;
      case SortOptionMyMeetings.newCreated:
        return context.local.sort_new_created;
      case SortOptionMyMeetings.past:
        return context.local.sort_past_meeting;
    }
  }
}

Future<void> showSortSheet(
  BuildContext context, {
  required MeetUpcomingTab currentTab,
  required dynamic selectedOption,
  required ValueChanged<dynamic> onSelect,
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
        final optionsCount = currentTab == MeetUpcomingTab.myRooms
            ? SortOptionMyRooms.values.length
            : SortOptionMyMeetings.values.length;
        // Approximate height (handle bar + padding)
        final contentHeight = (optionsCount * 64.0) + 100.0;
        final maxHeight = contentHeight > availableHeight
            ? availableHeight
            : contentHeight;

        return BaseBottomSheet(
          maxHeight: maxHeight,
          contentPadding: const EdgeInsets.only(bottom: 12),
          child: SafeArea(
            left: false,
            right: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BottomSheetHandleBar(),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _buildOptions(
                      context,
                      currentTab,
                      selectedOption,
                      onSelect,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

List<Widget> _buildOptions(
  BuildContext context,
  MeetUpcomingTab currentTab,
  dynamic selectedOption,
  ValueChanged<dynamic> onSelect,
) {
  if (currentTab == MeetUpcomingTab.myRooms) {
    return SortOptionMyRooms.values.map((option) {
      final isSelected = selectedOption == option;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: InkWell(
          onTap: () {
            onSelect(option);
            Navigator.pop(context);
            LocalToast.showToast(
              context,
              toastType: ToastType.normlight,
              context.local.sort_by(option.getLabel(context)),
            );
          },
          child: Row(
            children: [
              Expanded(
                child: Text(
                  option.getLabel(context),
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
    }).toList();
  } else {
    return SortOptionMyMeetings.values.map((option) {
      final isSelected = selectedOption == option;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: InkWell(
          onTap: () {
            onSelect(option);
            Navigator.pop(context);
            LocalToast.showToast(
              context,
              toastType: ToastType.normlight,
              context.local.sort_by(option.getLabel(context)),
            );
          },
          child: Row(
            children: [
              Expanded(
                child: Text(
                  option.getLabel(context),
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
    }).toList();
  }
}
