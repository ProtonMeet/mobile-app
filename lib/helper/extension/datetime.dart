import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

// 30 days in milliseconds
const int thirtyDaysInMilliseconds = thirtyDaysInSeconds * 1000;
// 30 days in seconds
const int thirtyDaysInSeconds = 30 * 24 * 60 * 60;

/// Converts a Unix timestamp (seconds) to a DateTime object in the specified timezone.
/// If the timezone is invalid, the function will return the UTC DateTime.
///
/// Returns the DateTime object in the specified timezone or UTC if the timezone is invalid.
///
/// [seconds] - The Unix timestamp in seconds.
/// [timeZone] - The timezone to convert the DateTime to.
///
/// Returns the DateTime object in the specified timezone or UTC if the timezone is invalid.
DateTime? fromUnixSecondsWithTimeZone(int? seconds, String? timeZone) {
  if (seconds == null) return null;
  // Parse Unix timestamp (seconds) as UTC
  final utcDateTime = DateTime.fromMillisecondsSinceEpoch(
    seconds * 1000,
    isUtc: true,
  );

  // Convert to local timezone if no timezone specified
  if (timeZone == null || timeZone.isEmpty) {
    // Convert UTC DateTime to local timezone
    return utcDateTime.toLocal();
  }

  try {
    final location = tz.getLocation(timeZone);
    // Convert UTC timestamp to the target timezone
    final tzDateTime = tz.TZDateTime.fromMicrosecondsSinceEpoch(
      location,
      seconds * 1000000, // Convert seconds to microseconds
    );
    // Return as regular DateTime for compatibility with existing code
    return DateTime(
      tzDateTime.year,
      tzDateTime.month,
      tzDateTime.day,
      tzDateTime.hour,
      tzDateTime.minute,
      tzDateTime.second,
    );
  } catch (e) {
    // If timezone is invalid, fall back to UTC
    return utcDateTime;
  }
}

/// An extension on [DateTime] to get the Unix timestamp in seconds.
extension UnixTimestampExtension on DateTime {
  /// Returns the number of whole seconds since the Unix epoch (January 1, 1970).
  int secondsSinceEpoch() {
    return millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond;
  }
}

/// Extension to check if a date/time combination is in the future, respecting timezone.
extension DateTimeTimezoneExtension on DateTime {
  /// Checks if the given date/time combination is in the future, respecting the specified timezone.
  ///
  /// [time] - The time of day to combine with this date.
  /// [timeZone] - The timezone to use for comparison. If null or invalid, falls back to local timezone.
  ///
  /// Returns true if the date/time is in the future, false otherwise.
  bool isDateTimeInFuture(TimeOfDay time, String? timeZone) {
    try {
      if (timeZone != null && timeZone.isNotEmpty) {
        final location = tz.getLocation(timeZone);
        // Create TZDateTime from date/time in the specified timezone
        final selectedTZDateTime = tz.TZDateTime(
          location,
          year,
          month,
          day,
          time.hour,
          time.minute,
        );
        // Get current time in the same timezone
        final nowTZDateTime = tz.TZDateTime.now(location);
        // Check if selected time is after now
        return selectedTZDateTime.isAfter(nowTZDateTime);
      }
    } catch (e) {
      // Fallback to local timezone if timezone is invalid
    }

    // Fallback: check in local timezone
    final selectedDateTime = DateTime(year, month, day, time.hour, time.minute);
    return selectedDateTime.isAfter(DateTime.now());
  }

  /// Gets the minimum DateTime (current time) if this date is today in the specified timezone.
  ///
  /// This is useful for time pickers where you want to prevent selecting past times
  /// when the selected date is today.
  ///
  /// [timeZone] - The timezone to check if the date is today. If null or invalid, falls back to local timezone.
  ///
  /// Returns a DateTime with the current time if this date is today in the specified timezone,
  /// or null if the date is not today or timezone is invalid.
  DateTime? getMinimumTimeIfToday(String? timeZone) {
    try {
      if (timeZone != null && timeZone.isNotEmpty) {
        final location = tz.getLocation(timeZone);
        final tzNow = tz.TZDateTime.now(location);
        final tzToday = tz.TZDateTime(
          location,
          tzNow.year,
          tzNow.month,
          tzNow.day,
        );
        final tzThisDate = tz.TZDateTime(location, year, month, day);

        // If this date is today in the selected timezone, return current time
        if (tzThisDate.year == tzToday.year &&
            tzThisDate.month == tzToday.month &&
            tzThisDate.day == tzToday.day) {
          // Convert timezone-aware time to local DateTime for the picker
          return DateTime(year, month, day, tzNow.hour, tzNow.minute);
        }
      }
    } catch (e) {
      // Fallback: check if date is today in local timezone
    }

    // Fallback: check if date is today in local timezone
    final today = DateUtils.dateOnly(DateTime.now());
    final thisDateOnly = DateUtils.dateOnly(this);
    if (thisDateOnly.year == today.year &&
        thisDateOnly.month == today.month &&
        thisDateOnly.day == today.day) {
      final now = DateTime.now();
      return DateTime(year, month, day, now.hour, now.minute);
    }

    return null;
  }
}
