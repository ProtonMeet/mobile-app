import 'package:flutter/material.dart';
import 'package:meet/constants/app.config.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/datetime.dart';
import 'package:meet/rust/proton_meet/models/meeting_type.dart';
import 'package:meet/rust/proton_meet/models/upcoming_meeting.dart';
import 'package:meet/views/scenes/dashboard/schedule/schedule_meeting_dialog.dart';

extension FrbUpcomingMeetingExtension on FrbUpcomingMeeting {
  /// Returns true if this meeting is a personal meeting room.
  bool get isPersonalMeeting => meetingType == MeetingType.personal;

  /// Formats the meeting link URL with the meeting ID and password.
  /// Returns a full URL string that can be used to join the meeting.
  String formatMeetingLink() {
    return "${appConfig.apiEnv.baseUrl}/join/id-$meetingLinkName#pwd-$meetingPassword";
  }

  /// Formats the start date and time of the meeting.
  ///
  /// Returns a formatted string like "Monday 15 January, 14:30 - 15:00"
  /// or "Monday 15 January, 2:30 PM - 3:00 PM" depending on the format.
  ///
  /// [useLocalTimezone] - If true, displays time in device's local timezone;
  ///                      if false, uses the meeting's timezone.
  /// [use24HourFormat] - If provided, uses 24-hour format; otherwise uses
  ///                     device's default format setting.
  String formatStartDateTime(
    BuildContext context, {
    required bool useLocalTimezone,
    bool? use24HourFormat = false,
    bool? twoLines = false,
  }) {
    // Convert to local timezone if requested, otherwise use meeting's timezone
    final timeZoneToUse = useLocalTimezone ? null : timeZone;
    final start = fromUnixSecondsWithTimeZone(startTime, timeZoneToUse);
    if (start == null) return '';
    final end = fromUnixSecondsWithTimeZone(endTime, timeZoneToUse);
    final use24 =
        use24HourFormat ?? MediaQuery.of(context).alwaysUse24HourFormat;
    final weekday = context.weekdayNames[start.weekday - 1];
    final day = start.day;
    final month = context.monthNames[start.month - 1];
    final year = start.year;
    final startTimeText = _formatTime(context, start, use24HourFormat: use24);

    if (end == null) {
      if (twoLines == true) {
        return '$weekday, $month $day $year\n$startTimeText';
      }
      return '$weekday, $month $day $year, $startTimeText';
    }

    final endTimeText = _formatTime(context, end, use24HourFormat: use24);
    if (twoLines == true) {
      return '$weekday, $month $day $year\n$startTimeText - $endTimeText';
    }
    return '$weekday, $month $day $year, $startTimeText - $endTimeText';
  }

  /// Formats only the start and end time of the meeting (without date).
  ///
  /// Returns a formatted string like "14:30 - 15:00" or "2:30 PM - 3:00 PM".
  ///
  /// [useLocalTimezone] - If true, displays time in device's local timezone;
  ///                      if false, uses the meeting's timezone.
  /// [use24HourFormat] - If provided, uses 24-hour format; otherwise uses
  ///                     device's default format setting.
  String formatStartOnlyTime(
    BuildContext context, {
    required bool useLocalTimezone,
    bool? use24HourFormat = false,
  }) {
    final timeZoneToUse = useLocalTimezone ? null : timeZone;
    final start = fromUnixSecondsWithTimeZone(startTime, timeZoneToUse);
    if (start == null) return '';
    final end = fromUnixSecondsWithTimeZone(endTime, timeZoneToUse);
    final use24 =
        use24HourFormat ?? MediaQuery.of(context).alwaysUse24HourFormat;
    final startTimeText = _formatTime(context, start, use24HourFormat: use24);
    if (end == null) {
      return startTimeText;
    }
    final endTimeText = _formatTime(context, end, use24HourFormat: use24);
    return '$startTimeText - $endTimeText';
  }

  /// Formats the creation time of the meeting in a relative format.
  ///
  /// Returns localized strings like "Created today", "Created yesterday",
  /// "Created last week", or "Created on ['month'] ['day'], ['year']".
  ///
  /// [useLocalTimezone] - If true, displays time in device's local timezone;
  ///                      if false, uses the meeting's timezone.
  String formatCreateTime(
    BuildContext context, {
    required bool useLocalTimezone,
  }) {
    final timeZoneToUse = useLocalTimezone ? null : timeZone;
    final created = fromUnixSecondsWithTimeZone(createTime, timeZoneToUse);
    if (created == null) return '';

    final localCreateTime = created.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final createdDay = DateTime(
      localCreateTime.year,
      localCreateTime.month,
      localCreateTime.day,
    );
    final createdTimeText = _formatTime(
      context,
      localCreateTime,
      use24HourFormat: false,
    );

    final daysAgo = today.difference(createdDay).inDays;

    if (daysAgo == 0) {
      return "${context.local.created_today} · $createdTimeText";
    }
    if (daysAgo == 1) {
      return "${context.local.created_yesterday} · $createdTimeText";
    }
    final month = context.monthNames[localCreateTime.month - 1];
    final yearSuffix = createdDay.year != now.year
        ? ', ${createdDay.year}'
        : '';
    return "${context.local.created} $month ${localCreateTime.day}$yearSuffix · $createdTimeText";
  }

  /// Formats the last used time of the meeting in a date format.
  ///
  /// Returns localized string like "Last used on January 15, 2024".
  ///
  /// [useLocalTimezone] - If true, displays time in device's local timezone;
  ///                      if false, uses the meeting's timezone.
  String formatLastUsedTime(
    BuildContext context, {
    required bool useLocalTimezone,
  }) {
    if (lastUsedTime == null) return '';
    final timeZoneToUse = useLocalTimezone ? null : timeZone;
    final lastUsed = fromUnixSecondsWithTimeZone(lastUsedTime, timeZoneToUse);
    if (lastUsed == null) return '';

    final localLastUsedTime = lastUsed.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastUsedDay = DateTime(
      localLastUsedTime.year,
      localLastUsedTime.month,
      localLastUsedTime.day,
    );
    final daysAgo = today.difference(lastUsedDay).inDays;
    final lastUsedTimeText = _formatTime(
      context,
      localLastUsedTime,
      use24HourFormat: false,
    );

    if (daysAgo == 0) {
      return "${context.local.last_used_today} · $lastUsedTimeText";
    }
    if (daysAgo == 1) {
      return "${context.local.last_used_yesterday} · $lastUsedTimeText";
    }
    final month = context.monthNames[localLastUsedTime.month - 1];
    final currentYear = now.year;
    final yearSuffix = localLastUsedTime.year != currentYear
        ? ', ${localLastUsedTime.year}'
        : '';
    return "${context.local.last_used} $month ${localLastUsedTime.day}$yearSuffix · $lastUsedTimeText";
  }

  /// Formats the last used time of the meeting in a date format.
  ///
  /// Returns localized string like "Last used on January 15, 2024".
  ///
  /// [useLocalTimezone] - If true, displays time in device's local timezone;
  ///                      if false, uses the meeting's timezone.
  String formatPastTime(
    BuildContext context, {
    required bool useLocalTimezone,
  }) {
    if (lastUsedTime == null) return '';
    final timeZoneToUse = useLocalTimezone ? null : timeZone;
    final lastUsed = fromUnixSecondsWithTimeZone(lastUsedTime, timeZoneToUse);
    if (lastUsed == null) return '';

    final localLastUsedTime = lastUsed.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastUsedDay = DateTime(
      localLastUsedTime.year,
      localLastUsedTime.month,
      localLastUsedTime.day,
    );
    final daysAgo = today.difference(lastUsedDay).inDays;
    final lastUsedTimeText = _formatTime(
      context,
      localLastUsedTime,
      use24HourFormat: false,
    );

    if (daysAgo == 0) {
      return "${context.local.ended_today} · $lastUsedTimeText";
    }
    if (daysAgo == 1) {
      return "${context.local.ended_yesterday} · $lastUsedTimeText";
    }
    final month = context.monthNames[localLastUsedTime.month - 1];
    final currentYear = now.year;
    final yearSuffix = localLastUsedTime.year != currentYear
        ? ', ${localLastUsedTime.year}'
        : '';
    return "${context.local.ended_on} $month ${localLastUsedTime.day}$yearSuffix · $lastUsedTimeText";
  }

  /// Formats the creation time of the meeting in a normal date format.
  ///
  /// Returns a formatted string like "Created on January 15, 2024".
  ///
  /// [useLocalTimezone] - If true, displays time in device's local timezone;
  ///                      if false, uses the meeting's timezone.
  String formatCreateTimeNormal(
    BuildContext context, {
    required bool useLocalTimezone,
  }) {
    final timeZoneToUse = useLocalTimezone ? null : timeZone;
    final created = fromUnixSecondsWithTimeZone(createTime, timeZoneToUse);
    if (created == null) return '';
    final localCreateTime = created.toLocal();
    final month = context.monthNames[localCreateTime.month - 1];
    return context.local.created_on(
      month,
      localCreateTime.day,
      localCreateTime.year,
    );
  }

  /// Formats a DateTime object as a time string.
  ///
  /// Returns formatted time like "14:30" (24-hour) or "2:30 PM" (12-hour).
  ///
  /// [date] - The DateTime to format.
  /// [use24HourFormat] - If true, uses 24-hour format; otherwise uses 12-hour format with AM/PM.
  String _formatTime(
    BuildContext context,
    DateTime date, {
    required bool use24HourFormat,
  }) {
    final minute = date.minute.toString().padLeft(2, '0');
    if (use24HourFormat) {
      final hour = date.hour.toString().padLeft(2, '0');
      return '$hour:$minute';
    }

    final hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final suffix = date.hour >= 12
        ? context.local.time_pm
        : context.local.time_am;
    return '$hour12:$minute $suffix';
  }

  /// Checks if this meeting is a scheduled or recurring meeting.
  ///
  /// Returns true if the meeting type is scheduled or recurring
  /// and has a valid start time.
  bool isMyMeetings() {
    if (meetingType == MeetingType.scheduled ||
        meetingType == MeetingType.recurring) {
      if (startTime != null && startTime! > 0) {
        return true;
      }
    }
    return false;
  }

  /// Gets the meeting date/time in the specified timezone.
  ///
  /// Returns the start date/time as a DateTime object, or null if the meeting
  /// is not a scheduled/recurring meeting.
  ///
  /// [useLocalTimezone] - If true, returns time in device's local timezone;
  ///                      if false, returns time in the meeting's timezone.
  DateTime? getMeetingDate({required bool useLocalTimezone}) {
    final timeZoneToUse = useLocalTimezone ? null : timeZone;
    if (!isMyMeetings()) {
      return null;
    }
    return fromUnixSecondsWithTimeZone(startTime, timeZoneToUse);
  }

  /// Gets the last used date/time in the specified timezone.
  ///
  /// Returns the last used time as a DateTime object, or null if lastUsedTime is null.
  ///
  /// [useLocalTimezone] - If true, returns time in device's local timezone;
  ///                      if false, returns time in the meeting's timezone.
  DateTime? getLastUsedDate({required bool useLocalTimezone}) {
    if (lastUsedTime == null) {
      return null;
    }
    final timeZoneToUse = useLocalTimezone ? null : timeZone;
    return fromUnixSecondsWithTimeZone(lastUsedTime, timeZoneToUse);
  }

  /// Gets the creation date/time in the specified timezone.
  ///
  /// Returns the creation time as a DateTime object, or null if createTime is null.
  ///
  /// [useLocalTimezone] - If true, returns time in device's local timezone;
  ///                      if false, returns time in the meeting's timezone.
  DateTime? getCreateDate({required bool useLocalTimezone}) {
    if (createTime == null) {
      return null;
    }
    final timeZoneToUse = useLocalTimezone ? null : timeZone;
    return fromUnixSecondsWithTimeZone(createTime, timeZoneToUse);
  }

  /// Converts this meeting to ScheduleMeetingData for editing.
  ///
  /// Returns a ScheduleMeetingData object populated with the meeting's
  /// title, start date/time, duration, timezone, and recurrence settings.
  ///
  /// [useLocalTimezone] - If true, converts times to device's local timezone;
  ///                      if false, uses the meeting's timezone.
  ScheduleMeetingData toScheduleMeetingData({required bool useLocalTimezone}) {
    final timeZoneToUse = useLocalTimezone ? null : timeZone;
    final start = fromUnixSecondsWithTimeZone(startTime, timeZoneToUse);
    final end = fromUnixSecondsWithTimeZone(endTime, timeZoneToUse);
    final startDateTime = start ?? DateTime.now();
    final startTimeOfDay = TimeOfDay.fromDateTime(startDateTime);
    final durationMinutes = end != null
        ? end.difference(startDateTime).inMinutes
        : 30;
    final safeDuration = durationMinutes > 0 ? durationMinutes : 30;
    return ScheduleMeetingData(
      title: meetingName,
      startDate: DateTime(
        startDateTime.year,
        startDateTime.month,
        startDateTime.day,
      ),
      startTime: startTimeOfDay,
      durationMinutes: safeDuration,
      timeZone: timeZone,
      recurrence: _mapRRuleToRecurrence(rRule),
      showTimeZones: true,
    );
  }

  /// Maps an RRule string to a RecurrenceFrequency enum value.
  ///
  /// Parses the RRule string and returns the corresponding recurrence frequency.
  /// Returns [RecurrenceFrequency.none] if the RRule is invalid or empty.
  ///
  /// [rRule] - The RRule string (e.g., "FREQ=DAILY", "FREQ=WEEKLY").
  RecurrenceFrequency _mapRRuleToRecurrence(String? rRule) {
    if (rRule == null || rRule.isEmpty) {
      return RecurrenceFrequency.none;
    }
    final upper = rRule.toUpperCase();
    if (upper.contains('FREQ=DAILY')) {
      return RecurrenceFrequency.daily;
    }
    if (upper.contains('FREQ=WEEKLY')) {
      return RecurrenceFrequency.weekly;
    }
    if (upper.contains('FREQ=MONTHLY')) {
      return RecurrenceFrequency.monthly;
    }
    if (upper.contains('FREQ=YEARLY')) {
      return RecurrenceFrequency.yearly;
    }
    return RecurrenceFrequency.none;
  }
}
