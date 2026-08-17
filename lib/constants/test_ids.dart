/// Stable semantics identifiers for Appium / accessibility testing.
///
/// Use with [TestId] or pass to widgets that accept an optional `testId`.
abstract final class TestIds {
  // ── Screen / view roots ──────────────────────────────────────────────────

  static const dashboardScreen = 'meet.dashboard.screen';
  static const prejoinScreen = 'meet.prejoin.screen';
  static const roomScreen = 'meet.room.screen';

  // ── Dashboard — nav bar ─────────────────────────────────────────────────

  static const dashboardSignIn = 'meet.dashboard.sign_in';
  static const dashboardSettings = 'meet.dashboard.settings';
  static const dashboardUserMenu = 'meet.dashboard.user_menu';
  static const dashboardNavSearch = 'meet.dashboard.nav_search';
  static const dashboardNavSort = 'meet.dashboard.nav_sort';
  static const dashboardSearchField = 'meet.dashboard.search_field';
  static const dashboardSearchCancel = 'meet.dashboard.search_cancel';

  // ── Dashboard — tabs & lists ────────────────────────────────────────────

  static const dashboardTabMyMeetings = 'meet.dashboard.tab.my_meetings';
  static const dashboardTabMyRooms = 'meet.dashboard.tab.my_rooms';
  static const dashboardFetchReload = 'meet.dashboard.fetch_reload';
  static const dashboardSearchBar = 'meet.dashboard.search_bar';
  static const dashboardSort = 'meet.dashboard.sort';

  static String upcomingMeetingItem(int index) =>
      'meet.dashboard.upcoming_meeting_item.$index';

  // ── Dashboard — cards & guest entry ─────────────────────────────────────

  static const dashboardSignInCard = 'meet.dashboard.sign_in_card';
  static const dashboardSignInCardDismiss =
      'meet.dashboard.sign_in_card.dismiss';
  static const dashboardGuestPersonalMeeting =
      'meet.dashboard.guest_personal_meeting';

  // ── Dashboard — floating start menu ─────────────────────────────────────

  static const dashboardStartFab = 'meet.dashboard.start_fab';
  static const dashboardStartInstant = 'meet.dashboard.start.instant';
  static const dashboardStartSchedule = 'meet.dashboard.start.schedule';
  static const dashboardStartCreateRoom = 'meet.dashboard.start.create_room';
  static const dashboardStartJoinLink = 'meet.dashboard.start.join_link';

  // ── Dashboard — join / personal meeting dialog ────────────────────────────

  static const joinDialog = 'meet.dashboard.join_dialog';
  static const joinDialogLinkField = 'meet.dashboard.join_dialog.link_field';
  static const joinDialogJoin = 'meet.dashboard.join_dialog.join';
  static const joinDialogCopy = 'meet.dashboard.join_dialog.copy';
  static const joinDialogRegenerate = 'meet.dashboard.join_dialog.regenerate';
  static const joinDialogDone = 'meet.dashboard.join_dialog.done';
  static const joinDialogAddCalendar =
      'meet.dashboard.join_dialog.add_calendar';

  // ── Prejoin ─────────────────────────────────────────────────────────────

  static const prejoinPreview = 'meet.prejoin.preview';
  static const prejoinClose = 'meet.prejoin.close';
  static const prejoinCopyMeetingCode = 'meet.prejoin.copy_meeting_code';
  static const prejoinDisplayNameField = 'meet.prejoin.display_name_field';
  static const prejoinRememberName = 'meet.prejoin.remember_name';
  static const prejoinJoin = 'meet.prejoin.join';
  static const prejoinCreate = 'meet.prejoin.create';
  static const prejoinLeaveWaiting = 'meet.prejoin.leave_waiting';
  static const prejoinMicToggle = 'meet.prejoin.mic_toggle';
  static const prejoinVideoToggle = 'meet.prejoin.video_toggle';
  static const prejoinSwapCamera = 'meet.prejoin.swap_camera';
  static const prejoinBackgroundBlur = 'meet.prejoin.background_blur';
  static const prejoinSpeaker = 'meet.prejoin.speaker';
  static const prejoinWaitingRoomStatus = 'meet.prejoin.waiting_room_status';

  // ── Room — controls bar ─────────────────────────────────────────────────

  static const roomMic = 'meet.room.controls.mic';
  static const roomVideo = 'meet.room.controls.video';
  static const roomLeave = 'meet.room.controls.leave';
  static const roomMore = 'meet.room.controls.more';
  static const roomSpeakerMute = 'meet.room.controls.speaker_mute';
  static const roomReactions = 'meet.room.controls.reactions';
  static const roomPip = 'meet.room.controls.pip';
  static const roomScreenShare = 'meet.room.controls.screen_share';
  static const roomParticipants = 'meet.room.controls.participants';
  static const roomChat = 'meet.room.controls.chat';
  static const roomSettings = 'meet.room.controls.settings';
  static const roomInfo = 'meet.room.controls.info';

  // ── Room — top bar & misc ───────────────────────────────────────────────

  static const roomSwapCamera = 'meet.room.top_bar.swap_camera';
  static const roomSpeakerOutput = 'meet.room.top_bar.speaker_output';
  static const roomRotate = 'meet.room.rotate';
}
