import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/frb_upcoming_meeting.dart';
import 'package:meet/rust/proton_meet/models/upcoming_meeting.dart';
import 'package:meet/views/scenes/dashboard/dashboard_bloc.dart';
import 'package:meet/views/scenes/dashboard/join/join_meeting_dialog.dart';
import 'package:meet/views/scenes/room/get_participant_display_colors.dart';
import 'package:provider/provider.dart';

import 'upcoming/meet_upcoming_title.dart';
import 'upcoming/upcoming_meeting_list_item.dart';

class SearchResultsView extends StatelessWidget {
  const SearchResultsView({
    required this.searchQuery,
    required this.searchResults,
    required this.onJoinMeetingWithLink,
    required this.currentTab,
    super.key,
  });

  final String searchQuery;
  final List<FrbUpcomingMeeting> searchResults;
  final void Function(String roomId, String password, String meetingLink)
  onJoinMeetingWithLink;
  final MeetUpcomingTab currentTab;

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    if (searchQuery.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: keyboardHeight),
          child: Center(
            child: Text(
              context.local.start_typing_to_search,
              style: TextStyle(color: context.colors.textWeak),
            ),
          ),
        ),
      );
    }

    if (searchResults.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Padding(
          padding: EdgeInsets.only(left: 24, right: 24, bottom: keyboardHeight),
          child: Center(
            child: Text(
              context.local.no_results_found_for(searchQuery),
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.textWeak),
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: EdgeInsets.only(
        top: 8,
        bottom: keyboardHeight + 8,
        left: 24,
        right: 24,
      ),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final meeting = searchResults[index];
          final displayColors = getParticipantDisplayColors(context, index);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: UpcomingMeetingListItem(
              meeting: meeting,
              index: index,
              currentTab: currentTab,
              displayColors: displayColors,
              onJoin: () {
                final isPersonalMeeting = meeting.isPersonalMeeting;
                final meetingName = isPersonalMeeting
                    ? context.local.personal_meeting_room
                    : meeting.meetingName;
                showJoinMeetingDialog(
                  context,
                  bloc: context.read<DashboardBloc>(),
                  onJoin: onJoinMeetingWithLink,
                  initialUrl: meeting.formatMeetingLink(),
                  tab: currentTab,
                  autofocus: false,
                  editable: false,
                  meetingName: meetingName,
                  rRule: meeting.rRule,
                );
              },
            ),
          );
        }, childCount: searchResults.length),
      ),
    );
  }
}
