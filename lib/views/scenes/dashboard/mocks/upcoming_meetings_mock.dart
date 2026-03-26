import 'package:flutter/foundation.dart';
import 'package:meet/rust/proton_meet/models/meeting_type.dart';
import 'package:meet/rust/proton_meet/models/upcoming_meeting.dart';

/// Mock function to generate test data for all meeting types
/// Only available in debug mode
/// Returns empty list in release mode
List<FrbUpcomingMeeting> generateMockUpcomingMeetings() {
  if (!kDebugMode) {
    return [];
  }

  final now = DateTime.now();
  final tomorrow = now.add(const Duration(days: 1));
  final nextWeek = now.add(const Duration(days: 7));

  return [
    // Mock Personal Meeting
    FrbUpcomingMeeting(
      id: 'mock-personal-0',
      meetingLinkName: 'mock-personal-room-no-name',
      meetingName: '',
      meetingPassword: 'mock-pwd-123',
      meetingType: MeetingType.scheduled,
      startTime: now.millisecondsSinceEpoch ~/ 1000,
      endTime:
          now.add(const Duration(minutes: 30)).millisecondsSinceEpoch ~/ 1000,
      timeZone: DateTime.now().timeZoneName,
      protonCalendar: 0,
    ),
    // Mock Personal Meeting
    FrbUpcomingMeeting(
      id: 'mock-personal-1',
      meetingLinkName: 'mock-personal-room',
      meetingName: 'Mock Personal Meeting',
      meetingPassword: 'mock-pwd-123',
      meetingType: MeetingType.personal,
      protonCalendar: 0,
    ),
    // Mock Scheduled Meeting (today)
    FrbUpcomingMeeting(
      id: 'mock-scheduled-1',
      meetingLinkName: 'mock-scheduled-today',
      meetingName: 'Mock Scheduled Meeting Today',
      meetingPassword: 'mock-pwd-456',
      meetingType: MeetingType.scheduled,
      startTime: now.millisecondsSinceEpoch ~/ 1000,
      endTime: now.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
      timeZone: DateTime.now().timeZoneName,
      protonCalendar: 0,
    ),
    // Mock Scheduled Meeting (tomorrow)
    FrbUpcomingMeeting(
      id: 'mock-scheduled-2',
      meetingLinkName: 'mock-scheduled-tomorrow',
      meetingName: 'Mock Scheduled Meeting Tomorrow',
      meetingPassword: 'mock-pwd-789',
      meetingType: MeetingType.scheduled,
      startTime: tomorrow.millisecondsSinceEpoch ~/ 1000,
      endTime:
          tomorrow.add(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000,
      timeZone: DateTime.now().timeZoneName,
      protonCalendar: 0,
    ),
    // Mock Instant Meeting
    FrbUpcomingMeeting(
      id: 'mock-instant-1',
      meetingLinkName: 'mock-instant-room',
      meetingName: 'Mock Instant Meeting',
      meetingPassword: 'mock-pwd-instant',
      meetingType: MeetingType.instant,
      startTime: now.millisecondsSinceEpoch ~/ 1000,
      endTime: now.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
      timeZone: "Europe/Zurich",
      protonCalendar: 0,
    ),
    // Mock Recurring Meeting
    FrbUpcomingMeeting(
      id: 'mock-recurring-1',
      meetingLinkName: 'mock-recurring-room',
      meetingName: 'Mock Recurring Meeting (Weekly)',
      meetingPassword: 'mock-pwd-recurring',
      meetingType: MeetingType.recurring,
      startTime: (nextWeek.millisecondsSinceEpoch ~/ 1000),
      endTime:
          nextWeek.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
      rRule: 'FREQ=WEEKLY;BYDAY=MO',
      timeZone: 'UTC',
      protonCalendar: 0,
    ),
    // Mock Recurring Meeting (Daily)
    FrbUpcomingMeeting(
      id: 'mock-recurring-2',
      meetingLinkName: 'mock-recurring-daily',
      meetingName: 'Mock Recurring Meeting (Daily)',
      meetingPassword: 'mock-pwd-daily',
      meetingType: MeetingType.recurring,
      startTime: now.millisecondsSinceEpoch ~/ 1000,
      endTime: now.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
      rRule: 'FREQ=DAILY',
      timeZone: 'UTC',
      protonCalendar: 0,
    ),
  ];
}
