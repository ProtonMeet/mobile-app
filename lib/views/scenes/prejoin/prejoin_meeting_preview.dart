import 'package:meet/helper/extension/frb_upcoming_meeting.dart';
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/rust/proton_meet/models/meet_info.dart';
import 'package:meet/rust/proton_meet/models/meeting_info.dart';
import 'package:meet/rust/proton_meet/models/upcoming_meeting.dart';

/// Metadata resolved when the user presses Join (SRP auth + host check).
class PreJoinJoinAuthResult {
  const PreJoinJoinAuthResult({
    required this.meetInfo,
    required this.meetingInfo,
    required this.isMeetingHost,
    required this.authDisplayName,
  });

  final FrbMeetInfo meetInfo;
  final FrbMeetingInfo meetingInfo;
  final bool isMeetingHost;
  final String authDisplayName;
}

/// Builds [FrbMeetingInfo] for room UI from a decrypted join auth response.
/// Room code only reads participant limits / expiration from this object.
FrbMeetingInfo meetingInfoFromMeetPreview(FrbMeetInfo meetInfo) {
  return FrbMeetingInfo(
    meetingLinkName: meetInfo.meetLinkName,
    meetingName: meetInfo.meetName,
    salt: '',
    sessionKey: '',
    locked: meetInfo.isLocked ? 1 : 0,
    waitingRoom: meetInfo.hasWaitingRoom ? 1 : 0,
    maxDuration: meetInfo.maxDuration,
    maxParticipants: meetInfo.maxParticipants,
    expirationTime: meetInfo.expirationTime,
  );
}

FrbMeetingInfo meetingInfoWithWaitingRoom(
  FrbMeetingInfo meetingInfo, {
  required bool waitingRoomEnabled,
}) {
  return FrbMeetingInfo(
    meetingLinkName: meetingInfo.meetingLinkName,
    meetingName: meetingInfo.meetingName,
    salt: meetingInfo.salt,
    sessionKey: meetingInfo.sessionKey,
    locked: meetingInfo.locked,
    waitingRoom: waitingRoomEnabled ? 1 : 0,
    maxDuration: meetingInfo.maxDuration,
    maxParticipants: meetingInfo.maxParticipants,
    expirationTime: meetingInfo.expirationTime,
  );
}

/// Host context resolved from upcoming meetings (no SRP auth required).
class PreJoinHostMeetingContext {
  const PreJoinHostMeetingContext({
    required this.waitingRoomEnabled,
    this.roomName,
  });

  final bool waitingRoomEnabled;
  final String? roomName;
}

Future<PreJoinHostMeetingContext?> resolveHostMeetingContext({
  required AppCoreManager appCoreManager,
  required String meetingLinkName,
}) async {
  if (!appCoreManager.isAuthenticated || meetingLinkName.isEmpty) {
    return null;
  }
  try {
    final meetings = await appCoreManager.appCore.getUpcomingMeetings();
    for (final FrbUpcomingMeeting meeting in meetings) {
      if (meeting.meetingLinkName != meetingLinkName) {
        continue;
      }
      return PreJoinHostMeetingContext(
        waitingRoomEnabled: meeting.hasWaitingRoom,
        roomName: meeting.meetingName,
      );
    }
  } catch (_) {
    return null;
  }
  return null;
}

Future<PreJoinJoinAuthResult> authenticateForJoin({
  required AppCoreManager appCoreManager,
  required String meetingLinkName,
  required String meetingPassword,
  required String displayName,
  required bool isMeetingHost,
}) async {
  final meetInfo = await appCoreManager.appCore.authenticateMeetingLink(
    meetLinkName: meetingLinkName,
    meetLinkPassword: meetingPassword,
    displayName: displayName,
  );
  return PreJoinJoinAuthResult(
    meetInfo: meetInfo,
    meetingInfo: meetingInfoFromMeetPreview(meetInfo),
    isMeetingHost: isMeetingHost,
    authDisplayName: displayName,
  );
}
