import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/constants/test_ids.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/frb_upcoming_meeting.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/rust/proton_meet/models/meeting_type.dart';
import 'package:meet/rust/proton_meet/models/upcoming_meeting.dart';
import 'package:meet/rust/proton_meet/user_subscription.dart' as user_sub;
import 'package:meet/views/components/alerts/create_room_dialog.dart';
import 'package:meet/views/components/alerts/delete_meeting_dialog.dart';
import 'package:meet/views/components/test_id.dart';
import 'package:meet/views/scenes/dashboard/dashboard_bloc.dart';
import 'package:meet/views/scenes/dashboard/dashboard_event.dart';
import 'package:meet/views/scenes/dashboard/schedule/schedule_meeting_dialog.dart';
import 'package:meet/views/scenes/dashboard/search/sort_sheet.dart';
import 'package:meet/views/scenes/room/get_participant_display_colors.dart';
import 'package:meet/views/scenes/signin/auth_bloc.dart';
import 'package:meet/views/scenes/signin/auth_state.dart';

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

    return TestId(
      id: TestIds.upcomingMeetingItem(index),
      button: true,
      child: Material(
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
                      child: BlocSelector<AuthBloc, AuthState, bool>(
                        selector: (state) {
                          final user = state.user;
                          return user != null && user_sub.isPaid(user: user);
                        },
                        builder: (context, isPaidUser) {
                          return Text(
                            _resolveDisplayName(
                              context,
                              isPaidUser: isPaidUser,
                            ),
                            style: ProtonStyles.body1Semibold(
                              color: meeting.isPersonalMeeting
                                  ? context.colors.interActionNorm
                                  : context.colors.textNorm,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          );
                        },
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
              _buildTrailingAction(context),
            ],
          ),
        ),
      ),
    ),
    );
  }

  /// Resolves the title to show on the first line of the row.
  ///
  /// - Personal meeting room: prefers the user-set name, falls back to the
  ///   localized "Personal meeting room" placeholder when no custom name is
  ///   set.
  /// - Other meetings/rooms with a name: shows the user-set name as-is.
  /// - Other meetings/rooms without a name: falls back to a localized
  ///   placeholder that depends on the user's subscription status — paid
  ///   users see "Premium meeting", everyone else (including unauth users)
  ///   sees "Free meeting". This mirrors the default name written by
  ///   `_defaultInstantMeetingName` in `waiting_room_bloc.dart` for legacy
  ///   meetings created before the default name flow existed.
  String _resolveDisplayName(BuildContext context, {required bool isPaidUser}) {
    final name = meeting.meetingName;
    if (meeting.isPersonalMeeting) {
      return name.isEmpty ? context.local.personal_meeting_room : name;
    }
    if (name.isNotEmpty) {
      return name;
    }
    return isPaidUser
        ? context.local.premium_meeting
        : context.local.free_meeting;
  }

  /// Trailing action shown after the meeting name.
  ///
  /// - Personal meeting room (signed-in user): same overflow menu as other
  ///   rooms but with **only** the edit option (no delete).
  /// - Personal meeting room (unauth user): the legacy pin icon, since
  ///   editing requires sign-in.
  /// - All other meetings: overflow menu with edit + delete.
  Widget _buildTrailingAction(BuildContext context) {
    if (meeting.isPersonalMeeting) {
      return BlocSelector<AuthBloc, AuthState, bool>(
        selector: (state) => state.isSignedIn,
        builder: (context, isSignedIn) {
          if (!isSignedIn) {
            return Row(
              children: [
                context.images.iconPinAngled.svg20(
                  color: context.colors.protonBlue,
                ),
                const SizedBox(width: 2),
              ],
            );
          }
          return _buildOverflowMenu(context, allowDelete: false);
        },
      );
    }
    return _buildOverflowMenu(context, allowDelete: true);
  }

  Widget _buildOverflowMenu(BuildContext context, {required bool allowDelete}) {
    return PopupMenuButton<String>(
      icon: context.images.iconMore.svg20(color: context.colors.textDisable),
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
                    if (showEditButton)
                      UpcomingMenuItem(
                        icon: context.images.iconEdit.svg20(
                          color: context.colors.textNorm,
                        ),
                        label:
                            (meeting.isPersonalMeeting ||
                                currentTab == MeetUpcomingTab.myRooms)
                            ? context.local.edit_room
                            : context.local.edit_meeting,
                        labelColor: context.colors.textNorm,
                        onTap: () => _handleEdit(context),
                      ),
                    if (showEditButton && allowDelete)
                      const SizedBox(height: 24),
                    if (allowDelete)
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
      final authState = context.read<AuthBloc>().state;
      final user = authState.user;
      final isPaidUser = user != null && user_sub.isPaid(user: user);
      showEditScheduleMeetingDialog(
        context,
        initialData: initialData,
        isPaidUser: isPaidUser,
        displayColors: displayColors,
        showWaitingRoom: context.read<DashboardBloc>().isMeetWaitingRoomEnabled(),
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
