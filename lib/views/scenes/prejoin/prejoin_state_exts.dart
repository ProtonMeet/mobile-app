import 'package:meet/rust/proton_meet/models/upcoming_meeting.dart';
import 'package:meet/views/scenes/prejoin/prejoin_state.dart';

extension PreJoinStateExtension on PreJoinState {
  bool get isAwaitingWaitingRoomAdmission =>
      waitingRoomAdmissionPhase == WaitingRoomAdmissionPhase.awaitingAdmission;

  /// Meeting link when the guest is actively waiting for host admission.
  FrbUpcomingMeeting? get meetingLinkForAwaitingAdmission {
    if (!isAwaitingWaitingRoomAdmission) {
      return null;
    }
    return meetingLink;
  }
}
