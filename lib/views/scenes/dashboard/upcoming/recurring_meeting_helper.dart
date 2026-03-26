import 'package:meet/rust/proton_meet/models/meeting_type.dart';
import 'package:meet/rust/proton_meet/models/upcoming_meeting.dart';
import 'package:timezone/timezone.dart' as tz;

/// Helper class for handling recurring meeting adjustments
class RecurringMeetingHelper {
  /// Get the last day of a given month
  static int _getLastDayOfMonth(int year, int month) {
    // DateTime constructor automatically handles invalid dates by clamping
    // We can use this to get the last day by trying day 32 and letting it overflow
    final firstDayOfNextMonth = DateTime(year, month + 1);
    final lastDayOfMonth = firstDayOfNextMonth.subtract(
      const Duration(days: 1),
    );
    return lastDayOfMonth.day;
  }

  /// Check if a year is a leap year
  static bool _isLeapYear(int year) {
    return (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
  }

  /// Parse rRule to extract frequency (DAILY, WEEKLY, MONTHLY, YEARLY)
  static String? parseRecurrenceFrequency(String? rRule) {
    if (rRule == null || rRule.isEmpty) return null;

    final freqMatch = RegExp(
      r'FREQ=(\w+)',
      caseSensitive: false,
    ).firstMatch(rRule);
    return freqMatch?.group(1)?.toUpperCase();
  }

  /// Adjust recurring meeting times if they have passed
  /// Returns a new FrbUpcomingMeeting with updated startTime and endTime
  static FrbUpcomingMeeting adjustRecurringMeetingIfNeeded(
    FrbUpcomingMeeting meeting,
  ) {
    // Only process recurring meetings
    if (meeting.meetingType != MeetingType.recurring) {
      return meeting;
    }

    // Skip if no startTime
    if (meeting.startTime == null) {
      return meeting;
    }

    final now = DateTime.now().toUtc();
    final startTime = DateTime.fromMillisecondsSinceEpoch(
      meeting.startTime! * 1000,
      isUtc: true,
    );

    // If start time hasn't passed, no adjustment needed
    if (startTime.isAfter(now)) {
      return meeting;
    }

    // Parse frequency from rRule
    final frequency = parseRecurrenceFrequency(meeting.rRule);
    if (frequency == null) {
      return meeting; // Can't adjust without frequency
    }

    // Calculate next occurrence based on frequency
    DateTime nextStartTime;
    DateTime? nextEndTime;

    // Convert to meeting timezone if specified for accurate calculation
    if (meeting.timeZone != null && meeting.timeZone!.isNotEmpty) {
      try {
        final location = tz.getLocation(meeting.timeZone!);
        final tzStartTime = tz.TZDateTime.fromMicrosecondsSinceEpoch(
          location,
          meeting.startTime! * 1000000,
        );
        final tzNow = tz.TZDateTime.now(location);

        // Calculate next occurrence in timezone
        tz.TZDateTime tzNextStartTime;
        switch (frequency) {
          case 'DAILY':
            tzNextStartTime = tzStartTime.add(
              Duration(
                days: ((tzNow.difference(tzStartTime).inDays / 1).ceil()),
              ),
            );
            // Ensure it's in the future with iteration limit (max 366 days to handle leap years)
            int dailyIterations = 0;
            while ((tzNextStartTime.isBefore(tzNow) ||
                    tzNextStartTime.isAtSameMomentAs(tzNow)) &&
                dailyIterations < 366) {
              tzNextStartTime = tzNextStartTime.add(const Duration(days: 1));
              dailyIterations++;
            }
            // If still not in future after max iterations, return original meeting
            if (tzNextStartTime.isBefore(tzNow) ||
                tzNextStartTime.isAtSameMomentAs(tzNow)) {
              return meeting;
            }
          case 'WEEKLY':
            tzNextStartTime = tzStartTime.add(
              Duration(
                days: ((tzNow.difference(tzStartTime).inDays / 7).ceil() * 7),
              ),
            );
            // Ensure it's in the future with iteration limit (max 53 weeks)
            int weeklyIterations = 0;
            while ((tzNextStartTime.isBefore(tzNow) ||
                    tzNextStartTime.isAtSameMomentAs(tzNow)) &&
                weeklyIterations < 53) {
              tzNextStartTime = tzNextStartTime.add(const Duration(days: 7));
              weeklyIterations++;
            }
            // If still not in future after max iterations, return original meeting
            if (tzNextStartTime.isBefore(tzNow) ||
                tzNextStartTime.isAtSameMomentAs(tzNow)) {
              return meeting;
            }
          case 'MONTHLY':
            tzNextStartTime = tzStartTime;
            int monthlyIterations = 0;
            while ((tzNextStartTime.isBefore(tzNow) ||
                    tzNextStartTime.isAtSameMomentAs(tzNow)) &&
                monthlyIterations < 120) {
              // Calculate next month and year
              int nextYear = tzNextStartTime.year;
              int nextMonth = tzNextStartTime.month + 1;
              if (nextMonth > 12) {
                nextMonth = 1;
                nextYear++;
              }

              // Handle month boundary: clamp day to last day of target month
              int targetDay = tzNextStartTime.day;
              final lastDayOfMonth = _getLastDayOfMonth(nextYear, nextMonth);
              if (targetDay > lastDayOfMonth) {
                targetDay = lastDayOfMonth;
              }

              tzNextStartTime = tz.TZDateTime(
                location,
                nextYear,
                nextMonth,
                targetDay,
                tzNextStartTime.hour,
                tzNextStartTime.minute,
                tzNextStartTime.second,
              );
              monthlyIterations++;
            }
            // If still not in future after max iterations, return original meeting
            if (tzNextStartTime.isBefore(tzNow) ||
                tzNextStartTime.isAtSameMomentAs(tzNow)) {
              return meeting;
            }
          case 'YEARLY':
            tzNextStartTime = tzStartTime;
            int yearlyIterations = 0;
            while ((tzNextStartTime.isBefore(tzNow) ||
                    tzNextStartTime.isAtSameMomentAs(tzNow)) &&
                yearlyIterations < 10) {
              // Handle leap year edge case: if original date is Feb 29, adjust for non-leap years
              int targetDay = tzNextStartTime.day;
              final int targetMonth = tzNextStartTime.month;
              final nextYear = tzNextStartTime.year + 1;

              // If Feb 29 and next year is not a leap year, use Feb 28
              if (targetMonth == 2 &&
                  targetDay == 29 &&
                  !_isLeapYear(nextYear)) {
                targetDay = 28;
              }

              tzNextStartTime = tz.TZDateTime(
                location,
                nextYear,
                targetMonth,
                targetDay,
                tzNextStartTime.hour,
                tzNextStartTime.minute,
                tzNextStartTime.second,
              );
              yearlyIterations++;
            }
            // If still not in future after max iterations, return original meeting
            if (tzNextStartTime.isBefore(tzNow) ||
                tzNextStartTime.isAtSameMomentAs(tzNow)) {
              return meeting;
            }
          default:
            return meeting; // Unknown frequency
        }

        // Convert back to UTC timestamp
        nextStartTime = tzNextStartTime.toUtc();

        // Adjust endTime if present
        if (meeting.endTime != null) {
          final originalDuration = meeting.endTime! - meeting.startTime!;
          nextEndTime = nextStartTime.add(Duration(seconds: originalDuration));
        }
      } catch (e) {
        // If timezone conversion fails, fall back to UTC calculation
        return _adjustRecurringMeetingUtc(meeting, startTime, now, frequency);
      }
    } else {
      // No timezone specified, use UTC
      return _adjustRecurringMeetingUtc(meeting, startTime, now, frequency);
    }

    // Create new meeting with updated times
    return FrbUpcomingMeeting(
      id: meeting.id,
      addressId: meeting.addressId,
      meetingLinkName: meeting.meetingLinkName,
      meetingName: meeting.meetingName,
      meetingPassword: meeting.meetingPassword,
      meetingType: meeting.meetingType,
      startTime: nextStartTime.millisecondsSinceEpoch ~/ 1000,
      endTime: nextEndTime != null
          ? nextEndTime.millisecondsSinceEpoch ~/ 1000
          : null,
      rRule: meeting.rRule,
      timeZone: meeting.timeZone,
      protonCalendar: meeting.protonCalendar,
      createTime: meeting.createTime,
      lastUsedTime: meeting.lastUsedTime,
      calendarEventId: meeting.calendarEventId,
    );
  }

  /// Adjust recurring meeting using UTC (fallback when timezone conversion fails)
  static FrbUpcomingMeeting _adjustRecurringMeetingUtc(
    FrbUpcomingMeeting meeting,
    DateTime startTime,
    DateTime now,
    String frequency,
  ) {
    DateTime nextStartTime;
    DateTime? nextEndTime;

    switch (frequency) {
      case 'DAILY':
        nextStartTime = startTime.add(
          Duration(days: ((now.difference(startTime).inDays / 1).ceil())),
        );
        int dailyIterations = 0;
        while ((nextStartTime.isBefore(now) ||
                nextStartTime.isAtSameMomentAs(now)) &&
            dailyIterations < 366) {
          nextStartTime = nextStartTime.add(const Duration(days: 1));
          dailyIterations++;
        }
        // If still not in future after max iterations, return original meeting
        if (nextStartTime.isBefore(now) ||
            nextStartTime.isAtSameMomentAs(now)) {
          return meeting;
        }
      case 'WEEKLY':
        nextStartTime = startTime.add(
          Duration(days: ((now.difference(startTime).inDays / 7).ceil() * 7)),
        );
        int weeklyIterations = 0;
        while ((nextStartTime.isBefore(now) ||
                nextStartTime.isAtSameMomentAs(now)) &&
            weeklyIterations < 53) {
          nextStartTime = nextStartTime.add(const Duration(days: 7));
          weeklyIterations++;
        }
        // If still not in future after max iterations, return original meeting
        if (nextStartTime.isBefore(now) ||
            nextStartTime.isAtSameMomentAs(now)) {
          return meeting;
        }
      case 'MONTHLY':
        nextStartTime = startTime;
        int monthlyIterations = 0;
        while ((nextStartTime.isBefore(now) ||
                nextStartTime.isAtSameMomentAs(now)) &&
            monthlyIterations < 120) {
          // Calculate next month and year
          int nextYear = nextStartTime.year;
          int nextMonth = nextStartTime.month + 1;
          if (nextMonth > 12) {
            nextMonth = 1;
            nextYear++;
          }

          // Handle month boundary: clamp day to last day of target month
          int targetDay = nextStartTime.day;
          final lastDayOfMonth = _getLastDayOfMonth(nextYear, nextMonth);
          if (targetDay > lastDayOfMonth) {
            targetDay = lastDayOfMonth;
          }

          nextStartTime = DateTime(
            nextYear,
            nextMonth,
            targetDay,
            nextStartTime.hour,
            nextStartTime.minute,
            nextStartTime.second,
          );
          monthlyIterations++;
        }
        // If still not in future after max iterations, return original meeting
        if (nextStartTime.isBefore(now) ||
            nextStartTime.isAtSameMomentAs(now)) {
          return meeting;
        }
      case 'YEARLY':
        nextStartTime = startTime;
        int yearlyIterations = 0;
        while ((nextStartTime.isBefore(now) ||
                nextStartTime.isAtSameMomentAs(now)) &&
            yearlyIterations < 10) {
          // Handle leap year edge case: if original date is Feb 29, adjust for non-leap years
          int targetDay = nextStartTime.day;
          final int targetMonth = nextStartTime.month;
          final nextYear = nextStartTime.year + 1;

          // If Feb 29 and next year is not a leap year, use Feb 28
          if (targetMonth == 2 && targetDay == 29 && !_isLeapYear(nextYear)) {
            targetDay = 28;
          }

          nextStartTime = DateTime(
            nextYear,
            targetMonth,
            targetDay,
            nextStartTime.hour,
            nextStartTime.minute,
            nextStartTime.second,
          );
          yearlyIterations++;
        }
        // If still not in future after max iterations, return original meeting
        if (nextStartTime.isBefore(now) ||
            nextStartTime.isAtSameMomentAs(now)) {
          return meeting;
        }
      default:
        return meeting; // Unknown frequency
    }

    // Adjust endTime if present
    if (meeting.endTime != null) {
      final originalDuration = meeting.endTime! - meeting.startTime!;
      nextEndTime = nextStartTime.add(Duration(seconds: originalDuration));
    }

    // Create new meeting with updated times
    return FrbUpcomingMeeting(
      id: meeting.id,
      addressId: meeting.addressId,
      meetingLinkName: meeting.meetingLinkName,
      meetingName: meeting.meetingName,
      meetingPassword: meeting.meetingPassword,
      meetingType: meeting.meetingType,
      startTime: nextStartTime.millisecondsSinceEpoch ~/ 1000,
      endTime: nextEndTime != null
          ? nextEndTime.millisecondsSinceEpoch ~/ 1000
          : null,
      rRule: meeting.rRule,
      timeZone: meeting.timeZone,
      protonCalendar: meeting.protonCalendar,
      createTime: meeting.createTime,
      lastUsedTime: meeting.lastUsedTime,
      calendarEventId: meeting.calendarEventId,
    );
  }
}
