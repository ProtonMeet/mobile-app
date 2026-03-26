import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/frb_upcoming_meeting.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/rust/proton_meet/models/meeting_type.dart';
import 'package:meet/rust/proton_meet/models/upcoming_meeting.dart';
import 'package:meet/views/components/alerts/create_room_dialog.dart';
import 'package:meet/views/components/alerts/delete_meeting_dialog.dart';
import 'package:meet/views/scenes/dashboard/dashboard_bloc.dart';
import 'package:meet/views/scenes/dashboard/dashboard_event.dart';
import 'package:meet/views/scenes/dashboard/schedule/schedule_meeting_dialog.dart';
import 'package:meet/views/scenes/dashboard/search/sort_sheet.dart';
import 'package:meet/views/scenes/room/get_participant_display_colors.dart';

import 'meet_upcoming_title.dart';
import 'upcoming_menu_item.dart';

class UpcomingMeetingListItem extends StatelessWidget {
  final FrbUpcomingMeeting meeting;
  final VoidCallback onJoin;
  final int index;
  final bool showEditButton = true;
  final MeetUpcomingTab currentTab;
  final ParticipantDisplayColors displayColors;
  final SortOptionMyMeetings? sortOption;
  final SortOptionMyRooms? sortOptionMyRooms;

  const UpcomingMeetingListItem({
    required this.meeting,
    required this.onJoin,
    required this.index,
    required this.currentTab,
    required this.displayColors,
    this.sortOption,
    this.sortOptionMyRooms,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final fullTimeRange = meeting.formatStartOnlyTime(
      context,
      useLocalTimezone: true,
    );
    final timeCreated = meeting.formatCreateTime(
      context,
      useLocalTimezone: true,
    );

    final pastTime = meeting.formatPastTime(context, useLocalTimezone: true);

    final lastUsedTime = meeting.formatLastUsedTime(
      context,
      useLocalTimezone: true,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onJoin,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              if (meeting.isPersonalMeeting) ...[
                context.images.iconPersonalMeeting.svg40(),
              ] else ...[
                // meeting type icon
                Container(
                  width: 40,
                  height: 40,
                  padding: const EdgeInsets.all(12),
                  decoration: ShapeDecoration(
                    color: displayColors.backgroundColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: currentTab == MeetUpcomingTab.myRooms
                      ? context.images.iconMeetingPerson.svg(
                          colorFilter: ColorFilter.mode(
                            displayColors.profileColor,
                            BlendMode.srcIn,
                          ),
                        )
                      : context.images.iconMeetingCalendar.svg(
                          colorFilter: ColorFilter.mode(
                            displayColors.profileColor,
                            BlendMode.srcIn,
                          ),
                        ),
                ),
              ],

              const SizedBox(width: 16),

              /// meeting name and time range
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // first line
                    Opacity(
                      opacity: 0.90,
                      child: Text(
                        meeting.isPersonalMeeting
                            ? context.local.personal_meeting_room
                            : meeting.meetingName.isEmpty
                            ? context.local.secure_meeting
                            : meeting.meetingName,
                        style: ProtonStyles.body1Semibold(
                          color: meeting.isPersonalMeeting
                              ? context.colors.interActionNorm
                              : context.colors.textNorm,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // second line
                    if (sortOption == SortOptionMyMeetings.upcoming &&
                        fullTimeRange.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (meeting.meetingType == MeetingType.recurring) ...[
                            context.images.iconMeetingRecurring.svg12(
                              color: context.colors.textHint,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Flexible(
                            child: Text(
                              fullTimeRange,
                              style: ProtonStyles.body2Medium(
                                color: context.colors.textHint,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ] else if (meeting.isPersonalMeeting) ...[
                      const SizedBox(height: 4),
                      Text(
                        context.local.personal_meeting_description,
                        style: ProtonStyles.body2Medium(
                          color: context.colors.textHint,
                        ),
                      ),
                    ] else if (sortOptionMyRooms ==
                            SortOptionMyRooms.lastUsed &&
                        currentTab == MeetUpcomingTab.myRooms &&
                        lastUsedTime.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        lastUsedTime,
                        style: ProtonStyles.body2Medium(
                          color: context.colors.textHint,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ] else if (sortOption == SortOptionMyMeetings.past &&
                        currentTab == MeetUpcomingTab.myMeetings &&
                        lastUsedTime.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        pastTime,
                        style: ProtonStyles.body2Medium(
                          color: context.colors.textHint,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ] else if (timeCreated.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        timeCreated,
                        style: ProtonStyles.body2Medium(
                          color: context.colors.textHint,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              // Keep a right-side icon for personal meeting for visual consistency.
              if (meeting.meetingType == MeetingType.personal)
                Row(
                  children: [
                    context.images.iconPinAngled.svg20(
                      color: context.colors.protonBlue,
                    ),
                    const SizedBox(width: 2),
                  ],
                )
              else
                PopupMenuButton<String>(
                  icon: context.images.iconMore.svg20(
                    color: context.colors.textDisable,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  elevation: 0,
                  color: Colors.transparent,
                  itemBuilder: (BuildContext context) => [
                    PopupMenuItem<String>(
                      enabled: false,
                      padding: EdgeInsets.zero,
                      height: 0,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                          child: Container(
                            padding: const EdgeInsets.only(
                              top: 24,
                              left: 24,
                              right: 32,
                              bottom: 24,
                            ),
                            decoration: ShapeDecoration(
                              color: context.colors.backgroundPopupMenu,
                              shape: RoundedRectangleBorder(
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.04),
                                ),
                                borderRadius: BorderRadius.circular(24),
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (showEditButton) ...[
                                  UpcomingMenuItem(
                                    icon: context.images.iconEdit.svg20(
                                      color: context.colors.textNorm,
                                    ),
                                    label: currentTab == MeetUpcomingTab.myRooms
                                        ? context.local.edit_room
                                        : context.local.edit_meeting,
                                    labelColor: context.colors.textNorm,
                                    onTap: () => _handleEdit(context),
                                  ),
                                  const SizedBox(height: 24),
                                ],

                                UpcomingMenuItem(
                                  icon: context.images.iconDelete.svg20(
                                    color: context.colors.signalDanger,
                                  ),
                                  label: context.local.delete,
                                  labelColor: context.colors.signalDanger,
                                  onTap: () => _handleDelete(context),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleDelete(BuildContext context) async {
    final confirmed = await showDeleteMeetingDialog(context, meeting: meeting);

    if (confirmed == true && context.mounted) {
      // Trigger delete action in bloc
      context.read<DashboardBloc>().add(
        DeleteMeetingEvent(meetingId: meeting.id),
      );
    }
  }

  void _handleEdit(BuildContext context) {
    if (meeting.isMyMeetings()) {
      final initialData = meeting.toScheduleMeetingData(
        useLocalTimezone: false,
      );
      showEditScheduleMeetingDialog(
        context,
        initialData: initialData,
        displayColors: displayColors,
        onEdit: (data) {
          context.read<DashboardBloc>().add(
            UpdateScheduledMeetingEvent(meeting: meeting, data: data),
          );
        },
      );
    } else {
      showEditRoomDialog(
        context,
        initialRoomName: meeting.meetingName,
        displayColors: displayColors,
        onEditRoom: (roomName) {
          context.read<DashboardBloc>().add(
            UpdateMeetingEvent(meeting: meeting, updatedMeetingName: roomName),
          );
        },
      );
    }
  }
}
