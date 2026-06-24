import 'dart:io';

/// Desktop child client id for account desktop login fork payloads.
String desktopMeetChildClientId() {
  if (Platform.isMacOS) return 'macos-meet';
  if (Platform.isWindows) return 'windows-meet';
  if (Platform.isLinux) return 'linux-meet';
  return 'macos-meet';
}
