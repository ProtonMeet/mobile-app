import 'package:flutter/material.dart';
import 'package:meet/constants/assets.gen.dart';

/// Named, typed handles for every icon/logo the app renders, so call sites
/// reference `context.images.iconClose` instead of a raw asset path and a
/// rename in `assets.gen.dart` breaks the build rather than failing at runtime.
///
/// Most SVGs use a clear background and are tinted by the caller via
/// [ProtonColors], so a single asset serves both themes. Only the icons that
/// genuinely need different artwork branch on [isDark]; add new per-theme
/// icons by making the getter a ternary rather than by threading another
/// constructor argument through every call site.
@immutable
class ProtonImages extends ThemeExtension<ProtonImages> {
  const ProtonImages({required this.isDark});

  final bool isDark;

  /// landing page bar logo
  AssetGenImage get protonMeetBarLogo =>
      Assets.images.logos.protonMeetBarLogoClean;
  SvgGenImage get icAppNoWord => Assets.images.icon.icAppNoWord;

  /// top right settings
  SvgGenImage get iconClose => Assets.images.icon.icCross;
  SvgGenImage get iconSwapCamera => Assets.images.icon.icSwapCam;
  SvgGenImage get iconDeleteAccount => Assets.images.icon.icTrash;

  /// system
  SvgGenImage get iconSettings => Assets.images.icon.icCogWheel;

  /// control bar icons
  SvgGenImage get iconAudioOn => Assets.images.icon.icMicOn;
  SvgGenImage get iconAudioOff => Assets.images.icon.icMicOff;
  SvgGenImage get iconVideoOn => Assets.images.icon.icVideoOn;
  SvgGenImage get iconVideoOff => Assets.images.icon.icVideoOff;
  SvgGenImage get iconParticipants => Assets.images.icon.icPeople;
  SvgGenImage get iconInfo => Assets.images.icon.icInfoCircle;
  SvgGenImage get iconChat => Assets.images.icon.icChat;
  SvgGenImage get iconScreenShare => Assets.images.icon.icShareScreen;
  SvgGenImage get iconEndCall => Assets.images.icon.icHang;
  SvgGenImage get iconSpeakerOn => Assets.images.icon.icSpeakerOn;
  SvgGenImage get iconSpeakerOff => Assets.images.icon.icSpeakerOff;
  SvgGenImage get iconSpeakerPhone => Assets.images.icon.icSpeakerPhone;
  SvgGenImage get iconAudioOutputPhone => Assets.images.icon.icAudioOutputPhone;
  SvgGenImage get iconAudioOutputHeadphones =>
      Assets.images.icon.icAudioOutputHeadphones;
  SvgGenImage get iconAudioOutputBluetooth =>
      Assets.images.icon.icAudioOutputBluetooth;
  SvgGenImage get iconAudioOutputSpeakerphone =>
      Assets.images.icon.icAudioOutputSpeakerphone;
  SvgGenImage get iconMore => Assets.images.icon.icMore;
  SvgGenImage get iconReload => Assets.images.icon.icReload;

  /// icons for add to calendar
  SvgGenImage get iconAddToCalendar => Assets.images.icon.icSquareArrowUpRight;
  SvgGenImage get iconUploadFile => Assets.images.icon.icDataUpload;

  /// in room top bar
  SvgGenImage get iconDiamond => Assets.images.icon.icDiamond;
  SvgGenImage get iconDiamondClear => Assets.images.icon.icDiamondClear;
  SvgGenImage get iconStarShield => Assets.images.icon.icStarShield;

  /// icons for dashboard
  SvgGenImage get iconLink => Assets.images.icon.icLink;
  SvgGenImage get iconUser => Assets.images.icon.icUser;
  SvgGenImage get iconPhone => Assets.images.icon.icPhone;
  SvgGenImage get iconAdd => Assets.images.icon.icPlus;
  SvgGenImage get iconMeetingCalendar => Assets.images.icon.icMeetingsCalendar;
  SvgGenImage get iconMeetingPerson => Assets.images.icon.icMeetingsPeople;
  SvgGenImage get iconMeetingRecurring => Assets.images.icon.icRecurring;
  SvgGenImage get iconEdit => Assets.images.icon.icPenSquare;
  SvgGenImage get iconDelete => Assets.images.icon.icCrossCircle;
  SvgGenImage get iconCopy => Assets.images.icon.icSquares;
  SvgGenImage get iconSorting => Assets.images.icon.icSort;
  SvgGenImage get iconCheckmark => Assets.images.icon.icCheckmarkStrong;
  SvgGenImage get iconPinAngled => Assets.images.icon.icPinAngled;

  SvgGenImage get iconScheduleLogo => Assets.images.icon.icCalendarTitle;
  SvgGenImage get iconScheduleText => Assets.images.icon.icTextAlignLeft;
  SvgGenImage get iconScheduleToday => Assets.images.icon.icCalendarToday;
  SvgGenImage get iconScheduleTime => Assets.images.icon.icClock;
  SvgGenImage get iconScheduleTimeZone => Assets.images.icon.icEarth;
  SvgGenImage get iconScheduleRepeat => Assets.images.icon.icRecurring;
  SvgGenImage get iconScheduleWaitingRoom =>
      Assets.images.icon.icScheduleWaitingRoom;
  SvgGenImage get iconCalendarModalHeader =>
      Assets.images.icon.icCalendarModalHeader;
  SvgGenImage get iconDoorModalHeader => Assets.images.icon.icDoorModalHeader;
  SvgGenImage get iconPeopleModalHeader =>
      Assets.images.icon.icPeopleModalHeader;
  SvgGenImage get iconPersonalMeeting =>
      Assets.images.icon.icPersonalMeetingRoomAvatar;

  /// icons for room logo
  SvgGenImage get logoRoomPersonal => Assets.images.logos.meetingRoomPersonal;
  SvgGenImage get logoRoomBlue => Assets.images.logos.meetingRoomBlue1;
  SvgGenImage get logoRoomGreen => Assets.images.logos.meetingRoomGreen1;
  SvgGenImage get logoRoomRed => Assets.images.logos.meetingRoomRed1;
  SvgGenImage get logoRoomOrange => Assets.images.logos.meetingRoomOrange1;
  SvgGenImage get logoRoomPurple => Assets.images.logos.meetingRoomPurple1;

  SvgGenImage get logoScheduleBlue => Assets.images.logos.meetingScheduleBlue1;
  SvgGenImage get logoScheduleGreen =>
      Assets.images.logos.meetingScheduleGreen1;
  SvgGenImage get logoScheduleRed => Assets.images.logos.meetingScheduleRed1;
  SvgGenImage get logoScheduleOrange =>
      Assets.images.logos.meetingScheduleOrange1;
  SvgGenImage get logoSchedulePurple =>
      Assets.images.logos.meetingSchedulePurple1;

  SvgGenImage get defaultRoomLogo => Assets.images.logos.meetingRoomPurple1;

  /// icons for chat
  SvgGenImage get iconChatSend => Assets.images.icon.icChatSend;
  SvgGenImage get iconChatNoResult => Assets.images.icon.icChatNoResult;
  SvgGenImage get iconChatSearch => Assets.images.icon.icChatSearch;
  SvgGenImage get iconChatLogo => Assets.images.icon.icChatLogo;

  /// icons for participant list
  SvgGenImage get iconAudioOnWave => Assets.images.icon.icAudioWave;

  /// connection quality
  SvgGenImage get iconConnectionPoor => Assets.images.icon.icConnectionPoor;

  /// error/warning/notice
  SvgGenImage get iconErrorMessage => Assets.images.icon.icWarning;
  SvgGenImage get iconWarningMessage => Assets.images.icon.icWarning;
  SvgGenImage get iconSecurityIndicator =>
      Assets.images.icon.icSecurityIndicator;
  SvgGenImage get iconLeaveMeeting => isDark
      ? Assets.images.icon.icEarlyAccessDialog
      : Assets.images.icon.icMeetingShieldH;
  SvgGenImage get iconLeaveMeetingGuest =>
      Assets.images.icon.icLeaveMeetingGuest;
  SvgGenImage get iconLeftMeeting => Assets.images.icon.icLeftMeeting;
  SvgGenImage get iconInvalidLink => Assets.images.icon.icInvalidLink;
  SvgGenImage get iconValidLink => Assets.images.icon.icValidLink;
  SvgGenImage get iconLocked => Assets.images.icon.icLocked;

  /// icons for early access dialog
  SvgGenImage get iconEarlyAccess => Assets.images.icon.icEarlyAccessDialog;

  /// icons for feedbacks
  SvgGenImage get iconFeedbackStar => Assets.images.icon.icStarRateFilled;
  SvgGenImage get iconFeedbackStarBorder => Assets.images.icon.icStarRateEmpty;

  /// icons for session expired dialog
  SvgGenImage get iconSessionExpired => Assets.images.icon.icSessionExpired;

  /// icons for recording controls and dialogs
  SvgGenImage get iconRecording => Assets.images.icon.icRecording;

  @override
  ProtonImages copyWith({bool? isDark}) =>
      ProtonImages(isDark: isDark ?? this.isDark);

  /// Artwork can't be interpolated, so snap to the incoming theme's set.
  @override
  ProtonImages lerp(ThemeExtension<ProtonImages>? other, double t) =>
      other is ProtonImages ? other : this;
}

const lightImageExtension = ProtonImages(isDark: false);
const darkImageExtension = ProtonImages(isDark: true);
