/// Server-backed host toggles for the in-room settings panel.
abstract class InRoomHostSettingsTransport {
  Future<bool> toggleLockMeeting({required bool value});

  Future<bool> toggleWaitingRoom({required bool value});
}
