import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_sticky_header/flutter_sticky_header.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/frb_upcoming_meeting.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/rust/proton_meet/models/upcoming_meeting.dart';
import 'package:meet/views/scenes/dashboard/dashboard_bloc.dart';
import 'package:meet/views/scenes/dashboard/dashboard_event.dart';
import 'package:meet/views/scenes/dashboard/join/join_meeting_dialog.dart';
import 'package:meet/views/scenes/dashboard/search/sort_sheet.dart';
import 'package:meet/views/scenes/dashboard/upcoming/meeting_sticky_header.dart';
import 'package:meet/views/scenes/dashboard/upcoming/upcoming_meeting_item_action.dart';
import 'package:meet/views/scenes/room/get_participant_display_colors.dart';

import 'meet_upcoming_title.dart';
import 'upcoming_meeting_list_item.dart';

class UpcomingMeetingList extends StatelessWidget {
  const UpcomingMeetingList({
    required this.sortOption,
    required this.onJoinMeetingWithLink,
    required this.meetinsDisplay,
    required this.upcomingTab,
    required this.isLoaded,
    required this.onSchedule,
    required this.onCreateRoom,
    required this.sortOptionMyRooms,
    super.key,
  });

  final List<FrbUpcomingMeeting> meetinsDisplay;
  final MeetUpcomingTab upcomingTab;
  final bool isLoaded;
  final void Function(String roomId, String password, String meetingLink)
  onJoinMeetingWithLink;
  final VoidCallback onSchedule;
  final VoidCallback onCreateRoom;
  final SortOptionMyMeetings sortOption;
  final SortOptionMyRooms sortOptionMyRooms;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: buildUpcomingMeetingSlivers(
        context: context,
        meetinsDisplay: meetinsDisplay,
        upcomingTab: upcomingTab,
        isLoaded: isLoaded,
        onJoinMeetingWithLink: onJoinMeetingWithLink,
        onSchedule: onSchedule,
        onCreateRoom: onCreateRoom,
        sortOption: sortOption,
        sortOptionMyRooms: sortOptionMyRooms,
      ),
    );
  }
}

List<Widget> buildUpcomingMeetingSlivers({
  required BuildContext context,
  required List<FrbUpcomingMeeting> meetinsDisplay,
  required MeetUpcomingTab upcomingTab,
  required bool isLoaded,
  required void Function(String roomId, String password, String meetingLink)
  onJoinMeetingWithLink,
  required VoidCallback onSchedule,
  required VoidCallback onCreateRoom,
  required SortOptionMyMeetings sortOption,
  required SortOptionMyRooms sortOptionMyRooms,
}) {
  if (meetinsDisplay.isEmpty) {
    return [
      if (isLoaded && upcomingTab == MeetUpcomingTab.myMeetings)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: UpcomingMeetingItemAction(
              onTap: onSchedule,
              label: context.local.schedule_a_meeting,
              icon: context.images.iconAdd.svg20(),
            ),
          ),
        ),
      if (isLoaded && upcomingTab == MeetUpcomingTab.myRooms)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: UpcomingMeetingItemAction(
              onTap: onCreateRoom,
              label: context.local.create_new_room,
            ),
          ),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: 60)),
    ];
  }

  final slivers = <Widget>[];
  slivers.addAll(
    _buildMeetingSlivers(
      context: context,
      meetinsDisplay: meetinsDisplay,
      upcomingTab: upcomingTab,
      onJoinMeetingWithLink: onJoinMeetingWithLink,
      onCreateRoom: onCreateRoom,
      isLoaded: isLoaded,
      sortOption: sortOption,
      sortOptionMyRooms: sortOptionMyRooms,
    ),
  );
  if (isLoaded && upcomingTab == MeetUpcomingTab.myMeetings) {
    slivers.add(
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 12),
          child: UpcomingMeetingItemAction(
            onTap: onSchedule,
            label: context.local.schedule_a_meeting,
            icon: context.images.iconAdd.svg20(),
          ),
        ),
      ),
    );
  }
  if (isLoaded && upcomingTab == MeetUpcomingTab.myRooms) {
    slivers.add(
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 12),
          child: UpcomingMeetingItemAction(
            onTap: onCreateRoom,
            label: context.local.create_new_room,
          ),
        ),
      ),
    );
  }
  slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 60)));
  return slivers;
}

List<Widget> _buildMeetingSlivers({
  required BuildContext context,
  required List<FrbUpcomingMeeting> meetinsDisplay,
  required MeetUpcomingTab upcomingTab,
  required void Function(String roomId, String password, String meetingLink)
  onJoinMeetingWithLink,
  required VoidCallback onCreateRoom,
  required bool isLoaded,
  required SortOptionMyMeetings sortOption,
  required SortOptionMyRooms sortOptionMyRooms,
}) {
  if (upcomingTab != MeetUpcomingTab.myMeetings) {
    return [
      SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final meeting = meetinsDisplay[index];
          final meetingLink = meeting.formatMeetingLink();
          final displayColors = getParticipantDisplayColors(context, index);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              UpcomingMeetingListItem(
                displayColors: displayColors,
                meeting: meeting,
                currentTab: upcomingTab,
                index: index,
                sortOption: sortOption,
                sortOptionMyRooms: sortOptionMyRooms,
                onJoin: () {
                  final isPersonalMeeting = meeting.isPersonalMeeting;
                  final meetingName = isPersonalMeeting
                      ? context.local.personal_meeting_room
                      : meeting.meetingName;
                  showJoinMeetingDialog(
                    context,
                    tab: upcomingTab,
                    bloc: context.read<DashboardBloc>(),
                    displayColors: displayColors,
                    isPersonalMeeting: isPersonalMeeting,
                    onJoin: onJoinMeetingWithLink,
                    initialUrl: meetingLink,
                    meetingName: meetingName,
                    subtitle: meeting.formatCreateTimeNormal(
                      context,
                      useLocalTimezone: true,
                    ),
                    rRule: meeting.rRule,
                    editable: false,
                    autofocus: false,
                    onRegenerateLink: () {
                      context.read<DashboardBloc>().add(
                        RotatePersonalMeetingLinkEvent(),
                      );
                    },
                  );
                },
              ),
              if (index != meetinsDisplay.length - 1) const SizedBox(height: 4),
            ],
          );
        }, childCount: meetinsDisplay.length),
      ),
    ];
  }

  final slivers = <Widget>[];
  DateTime? lastDate;
  final currentGroup = <int>[];

  void flushGroup(DateTime groupDate, SortOptionMyMeetings sortOption) {
    if (currentGroup.isEmpty) {
      return;
    }
    final groupIndices = List<int>.of(currentGroup);
    final isFirstGroup = slivers.isEmpty;
    slivers.add(
      SliverStickyHeader.builder(
        builder: (context, state) {
          final baseColor = context.colors.backgroundDark;
          return ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: ColoredBox(
                color: baseColor.withValues(alpha: 0.3),
                child: MeetingStickyHeader(
                  label: _formatMeetingHeaderLabel(
                    context,
                    sortOption,
                    groupDate,
                    isFirst: isFirstGroup,
                  ),
                ),
              ),
            ),
          );
        },
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final meetingIndex = groupIndices[index];
            final meeting = meetinsDisplay[meetingIndex];
            final meetingLink = meeting.formatMeetingLink();
            final displayColors = getParticipantDisplayColors(
              context,
              meetingIndex,
            );
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                UpcomingMeetingListItem(
                  displayColors: displayColors,
                  meeting: meeting,
                  currentTab: upcomingTab,
                  index: meetingIndex,
                  sortOption: sortOption,
                  sortOptionMyRooms: sortOptionMyRooms,
                  onJoin: () {
                    final isPersonalMeeting = meeting.isPersonalMeeting;
                    final meetingName = isPersonalMeeting
                        ? context.local.personal_meeting_room
                        : meeting.meetingName;
                    final isScheduledMeeting = meeting.isMyMeetings();
                    final scheduleData = isScheduledMeeting
                        ? meeting.toScheduleMeetingData(useLocalTimezone: true)
                        : null;
                    final dashboardBloc = context.read<DashboardBloc>();

                    showJoinMeetingDialog(
                      context,
                      tab: upcomingTab,
                      bloc: context.read<DashboardBloc>(),
                      displayColors: displayColors,
                      isPersonalMeeting: isPersonalMeeting,
                      onJoin: onJoinMeetingWithLink,
                      initialUrl: meetingLink,
                      meetingName: meetingName,
                      subtitle: meeting.formatStartDateTime(
                        context,
                        useLocalTimezone: true,
                        twoLines: true,
                      ),
                      rRule: meeting.rRule,
                      editable: false,
                      autofocus: false,
                      onAdd: isScheduledMeeting && scheduleData != null
                          ? () {
                              dashboardBloc.add(
                                AddScheduledMeetingToCalendarEvent(
                                  data: scheduleData,
                                  meetingLink: meetingLink,
                                ),
                              );
                            }
                          : null,
                      onShare: isScheduledMeeting && scheduleData != null
                          ? () {
                              dashboardBloc.add(
                                DownloadScheduledMeetingIcsEvent(
                                  data: scheduleData,
                                  meetingLink: meetingLink,
                                ),
                              );
                            }
                          : null,
                      onOpenOutlook: isScheduledMeeting && scheduleData != null
                          ? () {
                              dashboardBloc.add(
                                OpenScheduledMeetingCalendarEvent(
                                  data: scheduleData,
                                  meetingLink: meetingLink,
                                  provider: CalendarProvider.outlook,
                                ),
                              );
                            }
                          : null,
                      onOpenGoogle: isScheduledMeeting && scheduleData != null
                          ? () {
                              dashboardBloc.add(
                                OpenScheduledMeetingCalendarEvent(
                                  data: scheduleData,
                                  meetingLink: meetingLink,
                                  provider: CalendarProvider.google,
                                ),
                              );
                            }
                          : null,
                      onOpenProton: isScheduledMeeting && scheduleData != null
                          ? () {
                              dashboardBloc.add(
                                OpenScheduledMeetingCalendarEvent(
                                  data: scheduleData,
                                  meetingLink: meetingLink,
                                  provider: CalendarProvider.proton,
                                ),
                              );
                            }
                          : null,
                    );
                  },
                ),
                if (meetingIndex != meetinsDisplay.length - 1)
                  const SizedBox(height: 4),
              ],
            );
          }, childCount: groupIndices.length),
        ),
      ),
    );
    currentGroup.clear();
  }

  for (var i = 0; i < meetinsDisplay.length; i++) {
    final meeting = meetinsDisplay[i];
    // Use appropriate date for grouping based on sort option:
    // - past: use lastUsedTime date
    // - newCreated: use createTime date
    // - otherwise: use meeting date
    DateTime? meetingDate;
    if (sortOption == SortOptionMyMeetings.past) {
      meetingDate = meeting.getLastUsedDate(useLocalTimezone: true);
    } else if (sortOption == SortOptionMyMeetings.newCreated) {
      meetingDate = meeting.getCreateDate(useLocalTimezone: true);
    } else {
      meetingDate = meeting.getMeetingDate(useLocalTimezone: true);
    }
    if (meetingDate == null) {
      continue;
    }
    if (lastDate == null ||
        DateUtils.dateOnly(meetingDate) != DateUtils.dateOnly(lastDate)) {
      if (lastDate != null) {
        flushGroup(lastDate, sortOption);
      }
      lastDate = meetingDate;
    }
    currentGroup.add(i);
  }
  if (lastDate != null) {
    flushGroup(lastDate, sortOption);
  }
  return slivers;
}

String _formatMeetingHeaderLabel(
  BuildContext context,
  SortOptionMyMeetings sortOption,
  DateTime date, {
  required bool isFirst,
}) {
  String prefix(String text) {
    if (!isFirst) {
      return text;
    }
    switch (sortOption) {
      case SortOptionMyMeetings.upcoming:
        return '${context.local.upcoming_prefix} $text';
      case SortOptionMyMeetings.past:
        return '${context.local.ended_prefix} $text';
      case SortOptionMyMeetings.newCreated:
        return '${context.local.created_prefix} $text';
    }
  }

  final today = DateUtils.dateOnly(DateTime.now());
  final target = DateUtils.dateOnly(date);
  final tomorrow = today.add(const Duration(days: 1));
  final yesterday = today.subtract(const Duration(days: 1));
  final month = context.monthNames[date.month - 1].toUpperCase();
  final day = date.day.toString().padLeft(2, '0');

  /// year suffix
  final currentYear = today.year;
  final yearSuffix = date.year != currentYear ? ', ${date.year}' : '';

  if (target == today) {
    return prefix('${context.local.upcoming_today} — $month $day$yearSuffix');
  }

  if (target == tomorrow) {
    return prefix(
      '${context.local.upcoming_tomorrow} — $month $day$yearSuffix',
    );
  }

  if (target == yesterday) {
    return prefix('${context.local.on_yesterday} — $month $day$yearSuffix');
  }

  return prefix('$month $day$yearSuffix');
}
