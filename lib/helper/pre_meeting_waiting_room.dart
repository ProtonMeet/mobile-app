import 'package:meet/rust/proton_meet/core.dart';

Future<void> updatePreMeetingWaitingRoomSetting({
  required AppCore appCore,
  required String meetLinkName,
  required bool enable,
}) {
  return appCore.updateWaitingRoomSettingPreMeeting(
    meetLinkName: meetLinkName,
    enable: enable,
  );
}

Future<bool> resolveCanManageWaitingRoom({
  required AppCore appCore,
  required String meetLinkName,
}) async {
  final info = await appCore.getMeetingInfo(meetingLinkName: meetLinkName);
  return info.manageWaitingRoom == 1;
}
