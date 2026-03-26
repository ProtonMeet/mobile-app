import 'package:flutter/widgets.dart';
import 'package:meet/rust/proton_meet/models/upcoming_meeting.dart';

import 'schedule/schedule_meeting_dialog.dart';
import 'search/sort_sheet.dart';
import 'upcoming/meet_upcoming_title.dart';

@immutable
abstract class DashboardBlocEvent {}

/// Initial Event with load data
class InitDashboardEvent extends DashboardBlocEvent {
  InitDashboardEvent();
}

class FetchUserStateEvent extends DashboardBlocEvent {
  FetchUserStateEvent();
}

class CreatePersonalMeetingEvent extends DashboardBlocEvent {
  final bool goPersonalMeeting;
  CreatePersonalMeetingEvent({required this.goPersonalMeeting});
}

class RotatePersonalMeetingLinkEvent extends DashboardBlocEvent {
  RotatePersonalMeetingLinkEvent();
}

class CreateSecureMeetingEvent extends DashboardBlocEvent {
  final bool goSecureMeeting;
  CreateSecureMeetingEvent({required this.goSecureMeeting});
}

class JoinMeetingWithLinkEvent extends DashboardBlocEvent {
  final String joinMeetingWithLinkUrl;
  JoinMeetingWithLinkEvent({required this.joinMeetingWithLinkUrl});
}

class ResetEarlyAccessDialogEvent extends DashboardBlocEvent {
  ResetEarlyAccessDialogEvent();
}

class DismissDashboardInfoCardEvent extends DashboardBlocEvent {
  final String id;
  DismissDashboardInfoCardEvent({required this.id});
}

class UpdateUpcomingStateEvent extends DashboardBlocEvent {
  final MeetUpcomingTab upcomingTab;
  UpdateUpcomingStateEvent({required this.upcomingTab});
}

class ResetDashboardStateEvent extends DashboardBlocEvent {
  ResetDashboardStateEvent();
}

class CreateMeetingEvent extends DashboardBlocEvent {
  final String roomName;
  CreateMeetingEvent({required this.roomName});
}

class DeleteMeetingEvent extends DashboardBlocEvent {
  final String meetingId;
  DeleteMeetingEvent({required this.meetingId});
}

class UpdateMeetingEvent extends DashboardBlocEvent {
  final FrbUpcomingMeeting meeting;
  final String updatedMeetingName;
  UpdateMeetingEvent({required this.meeting, required this.updatedMeetingName});
}

class ClearCreatedMeetingLinkEvent extends DashboardBlocEvent {
  ClearCreatedMeetingLinkEvent();
}

class RetryDashboardLoadEvent extends DashboardBlocEvent {
  RetryDashboardLoadEvent();
}

class ScheduleMeetingEvent extends DashboardBlocEvent {
  final ScheduleMeetingData data;
  ScheduleMeetingEvent({required this.data});
}

class UpdateScheduledMeetingEvent extends DashboardBlocEvent {
  final FrbUpcomingMeeting meeting;
  final ScheduleMeetingData data;
  final bool previewOnly;
  UpdateScheduledMeetingEvent({
    required this.meeting,
    required this.data,
    this.previewOnly = false,
  });
}

class DownloadScheduledMeetingIcsEvent extends DashboardBlocEvent {
  final ScheduleMeetingData data;
  final String? meetingLink;
  DownloadScheduledMeetingIcsEvent({required this.data, this.meetingLink});
}

class AddScheduledMeetingToCalendarEvent extends DashboardBlocEvent {
  final ScheduleMeetingData data;
  final String? meetingLink;
  AddScheduledMeetingToCalendarEvent({required this.data, this.meetingLink});
}

enum CalendarProvider { outlook, google, proton }

class OpenScheduledMeetingCalendarEvent extends DashboardBlocEvent {
  final ScheduleMeetingData data;
  final String? meetingLink;
  final CalendarProvider provider;
  OpenScheduledMeetingCalendarEvent({
    required this.data,
    required this.provider,
    this.meetingLink,
  });
}

class ClearScheduledMeetingSummaryEvent extends DashboardBlocEvent {
  ClearScheduledMeetingSummaryEvent();
}

class ClearScheduledMeetingIcsEvent extends DashboardBlocEvent {
  ClearScheduledMeetingIcsEvent();
}

class EnterSearchModeEvent extends DashboardBlocEvent {
  EnterSearchModeEvent();
}

class ExitSearchModeEvent extends DashboardBlocEvent {
  ExitSearchModeEvent();
}

class UpdateSearchQueryEvent extends DashboardBlocEvent {
  final String query;
  UpdateSearchQueryEvent({required this.query});
}

class UpdateSortOptionMyRoomsEvent extends DashboardBlocEvent {
  final SortOptionMyRooms sortOption;
  UpdateSortOptionMyRoomsEvent({required this.sortOption});
}

class UpdateSortOptionMyMeetingsEvent extends DashboardBlocEvent {
  final SortOptionMyMeetings sortOption;
  UpdateSortOptionMyMeetingsEvent({required this.sortOption});
}

class LoadSignInCardVisibilityEvent extends DashboardBlocEvent {
  LoadSignInCardVisibilityEvent();
}

class DismissSignInCardEvent extends DashboardBlocEvent {
  DismissSignInCardEvent();
}

class MeetingUpdateEvent extends DashboardBlocEvent {
  final List<FrbUpcomingMeeting> meetings;
  MeetingUpdateEvent({required this.meetings});
}
