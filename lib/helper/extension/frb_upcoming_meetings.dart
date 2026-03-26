import 'package:meet/helper/extension/frb_upcoming_meeting.dart';
import 'package:meet/rust/proton_meet/models/meeting_type.dart';
import 'package:meet/rust/proton_meet/models/upcoming_meeting.dart';
import 'package:meet/views/scenes/dashboard/search/sort_sheet.dart';
import 'package:meet/views/scenes/dashboard/upcoming/recurring_meeting_helper.dart';

extension FrbUpcomingMeetingsExtension on List<FrbUpcomingMeeting> {
  /// Compares two meetings by createTime (newest first).
  /// Returns: -1 if this is newer, 1 if other is newer, 0 if equal.
  static int compareByCreateTime(FrbUpcomingMeeting a, FrbUpcomingMeeting b) {
    if (a.createTime == null && b.createTime == null) return 0;
    if (a.createTime == null) return 1;
    if (b.createTime == null) return -1;
    return b.createTime!.compareTo(a.createTime!);
  }

  /// Compares two meetings by lastUsedTime (newest first).
  /// Falls back to createTime if both lastUsedTime are null.
  /// Returns: -1 if this is newer, 1 if other is newer, 0 if equal.
  static int compareByLastUsedTime(FrbUpcomingMeeting a, FrbUpcomingMeeting b) {
    if (a.lastUsedTime == null && b.lastUsedTime == null) {
      // Fall back to createTime
      return compareByCreateTime(a, b);
    }
    if (a.lastUsedTime == null) return 1;
    if (b.lastUsedTime == null) return -1;
    return b.lastUsedTime!.compareTo(a.lastUsedTime!);
  }

  /// Compares two meetings by lastUsedTime with fallback to startTime.
  /// Returns: -1 if this is more recent, 1 if other is more recent, 0 if equal.
  static int compareByLastUsedTimeWithStartTimeFallback(
    FrbUpcomingMeeting a,
    FrbUpcomingMeeting b,
  ) {
    if (a.lastUsedTime == null && b.lastUsedTime == null) {
      // Fall back to startTime
      if (a.startTime == null && b.startTime == null) return 0;
      if (a.startTime == null) return 1;
      if (b.startTime == null) return -1;
      return a.startTime!.compareTo(b.startTime!);
    }
    if (a.lastUsedTime == null) return 1;
    if (b.lastUsedTime == null) return -1;
    return b.lastUsedTime!.compareTo(a.lastUsedTime!);
  }

  /// Compares two meetings by startTime (upcoming first, then past).
  /// Future meetings come before past meetings, then sorted by time ascending.
  ///
  /// Note: startTime should be UTC Unix timestamps (seconds since epoch).
  /// This ensures correct comparison regardless of the user's local timezone.
  ///
  /// Returns: -1 if this should come first, 1 if other should come first, 0 if equal.
  static int compareByStartTimeUpcomingFirst(
    FrbUpcomingMeeting a,
    FrbUpcomingMeeting b,
  ) {
    if (a.startTime == null && b.startTime == null) return 0;
    if (a.startTime == null) return 1;
    if (b.startTime == null) return -1;

    return a.startTime!.compareTo(b.startTime!);
  }

  /// Compares two meetings by startTime (past first, then upcoming).
  /// Past meetings come before future meetings, then sorted by time descending.
  /// Returns: -1 if this should come first, 1 if other should come first, 0 if equal.
  static int compareByStartTimePastFirst(
    FrbUpcomingMeeting a,
    FrbUpcomingMeeting b,
    int currentTimestamp,
  ) {
    if (a.startTime == null && b.startTime == null) return 0;
    if (a.startTime == null) return 1;
    if (b.startTime == null) return -1;
    // Past meetings first, then future meetings
    final aIsPast = a.startTime! <= currentTimestamp;
    final bIsPast = b.startTime! <= currentTimestamp;
    if (aIsPast != bIsPast) {
      return aIsPast ? -1 : 1;
    }
    return b.startTime!.compareTo(a.startTime!);
  }

  /// Sorts rooms with personal meetings always appearing first.
  /// Other rooms are sorted based on the provided sort option.
  List<FrbUpcomingMeeting> sortRoomsWithPersonalFirst(
    SortOptionMyRooms sortOption,
  ) {
    // Separate personal meeting from other rooms
    final personalMeetings = <FrbUpcomingMeeting>[];
    final otherRooms = <FrbUpcomingMeeting>[];

    for (final meeting in this) {
      if (meeting.isPersonalMeeting) {
        personalMeetings.add(meeting);
      } else {
        otherRooms.add(meeting);
      }
    }

    // Sort other rooms based on sort option
    switch (sortOption) {
      case SortOptionMyRooms.newCreated:
        otherRooms.sort(compareByCreateTime);
      case SortOptionMyRooms.lastUsed:
        // Filter out rooms with null when sorting by lastUsed
        otherRooms.removeWhere((meeting) => meeting.lastUsedTime == null);
        otherRooms.sort(compareByLastUsedTime);
    }

    // Always put personal meetings first
    return [...personalMeetings, ...otherRooms];
  }

  /// Sorts meetings based on the provided sort option.
  List<FrbUpcomingMeeting> sortMeetings(SortOptionMyMeetings sortOption) {
    final sorted = List<FrbUpcomingMeeting>.from(this);
    switch (sortOption) {
      case SortOptionMyMeetings.upcoming:
        sorted.sort(compareByStartTimeUpcomingFirst);
      case SortOptionMyMeetings.newCreated:
        sorted.sort(compareByCreateTime);
      case SortOptionMyMeetings.past:
        // Filter out meetings with null endTime when sorting by past
        sorted.removeWhere((meeting) => meeting.lastUsedTime == null);
        sorted.sort(compareByLastUsedTime);
    }

    return sorted;
  }

  /// Filters meetings by type (scheduled, instant, recurring, or permanent),
  /// applies recurring meeting adjustments, and sorts by start time.
  ///
  /// Returns a sorted list of filtered meetings.
  List<FrbUpcomingMeeting> getFilteredAndSortedUpcomingMeetings() {
    return where(
        (meeting) =>
            meeting.meetingType == MeetingType.scheduled ||
            meeting.meetingType == MeetingType.instant ||
            meeting.meetingType == MeetingType.recurring ||
            meeting.meetingType == MeetingType.permanent,
      ).map(RecurringMeetingHelper.adjustRecurringMeetingIfNeeded).toList()
      ..sort((a, b) {
        // Handle null startTime values - put them at the end
        if (a.startTime == null && b.startTime == null) return 0;
        if (a.startTime == null) return 1;
        if (b.startTime == null) return -1;

        // Parse and compare startTime values
        try {
          final dateA = DateTime.fromMillisecondsSinceEpoch(
            a.startTime! * 1000,
          );
          final dateB = DateTime.fromMillisecondsSinceEpoch(
            b.startTime! * 1000,
          );
          return dateA.compareTo(dateB);
        } catch (e) {
          // If parsing fails, compare as integers
          return a.startTime!.compareTo(b.startTime!);
        }
      });
  }

  /// Filters meetings by type (scheduled, instant, or recurring) with valid start time,
  /// applies recurring meeting adjustments, and sorts by start time.
  ///
  /// Returns a sorted list of filtered meetings.
  List<FrbUpcomingMeeting> getFilteredAndSortedMyMeetings() {
    return where(
        (meeting) =>
            (meeting.meetingType == MeetingType.scheduled ||
                meeting.meetingType == MeetingType.instant ||
                meeting.meetingType == MeetingType.recurring) &&
            (meeting.startTime != null && meeting.startTime! > 0),
      ).map(RecurringMeetingHelper.adjustRecurringMeetingIfNeeded).toList()
      ..sort((a, b) {
        // Handle null startTime values - put them at the end
        if (a.startTime == null && b.startTime == null) return 0;
        if (a.startTime == null) return 1;
        if (b.startTime == null) return -1;

        // Parse and compare startTime values
        try {
          final dateA = DateTime.fromMillisecondsSinceEpoch(
            a.startTime! * 1000,
          );
          final dateB = DateTime.fromMillisecondsSinceEpoch(
            b.startTime! * 1000,
          );
          return dateA.compareTo(dateB);
        } catch (e) {
          // If parsing fails, compare as integers
          return a.startTime!.compareTo(b.startTime!);
        }
      });
  }

  /// Filters meetings by type (scheduled, instant, recurring, or permanent) without valid start time,
  /// applies recurring meeting adjustments, and sorts by start time.
  ///
  /// Returns a sorted list of filtered meetings.
  List<FrbUpcomingMeeting> getFilteredAndSortedMyRooms() {
    return where(
        (meeting) =>
            (meeting.meetingType == MeetingType.scheduled ||
                meeting.meetingType == MeetingType.instant ||
                meeting.meetingType == MeetingType.recurring ||
                meeting.meetingType == MeetingType.permanent) &&
            (meeting.startTime == null || meeting.startTime! <= 0),
      ).map(RecurringMeetingHelper.adjustRecurringMeetingIfNeeded).toList()
      ..sort((a, b) {
        // Handle null startTime values - put them at the end
        if (a.startTime == null && b.startTime == null) return 0;
        if (a.startTime == null) return 1;
        if (b.startTime == null) return -1;

        // Parse and compare startTime values
        try {
          final dateA = DateTime.fromMillisecondsSinceEpoch(
            a.startTime! * 1000,
          );
          final dateB = DateTime.fromMillisecondsSinceEpoch(
            b.startTime! * 1000,
          );
          return dateA.compareTo(dateB);
        } catch (e) {
          // If parsing fails, compare as integers
          return a.startTime!.compareTo(b.startTime!);
        }
      });
  }
}
