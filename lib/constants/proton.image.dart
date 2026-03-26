import 'package:flutter/material.dart';
import 'package:meet/constants/assets.gen.dart';

/// Better performance and have better error handling during name mismatch.
/// Follows Flutter’s ThemeData structure makes it easier to manage with theming.
/// More scalable adding new icons is simpler.
/// Auto-applies light/dark icons when the theme changes.
///
///
/// if the svg image is using clear background with simple color. we can dirrect
///   use it with ProtonColors signle file will fit both light and dark theme
@immutable
class ProtonImages extends ThemeExtension<ProtonImages> {
  /// landing page bar logo
  final AssetGenImage protonMeetBarLogo;
  final SvgGenImage icAppNoWord;

  /// top right settings
  final SvgGenImage iconClose;
  final SvgGenImage iconSwapCamera;
  final SvgGenImage iconDeleteAccount;

  /// system
  final SvgGenImage iconSettings;

  /// control bar icons
  final SvgGenImage iconAudioOn;
  final SvgGenImage iconAudioOff;
  final SvgGenImage iconVideoOn;
  final SvgGenImage iconVideoOff;
  final SvgGenImage iconParticipants;
  final SvgGenImage iconInfo;
  final SvgGenImage iconChat;
  final SvgGenImage iconScreenShare;
  final SvgGenImage iconEndCall;
  final SvgGenImage iconSpeakerOn;
  final SvgGenImage iconSpeakerOff;
  final SvgGenImage iconSpeakerPhone;
  final SvgGenImage iconMore;
  final SvgGenImage iconReload;

  /// icons for add to calendar
  final SvgGenImage iconAddToCalendar;
  final SvgGenImage iconUploadFile;

  /// in room top bar
  final SvgGenImage iconDiamond;
  final SvgGenImage iconStarShield;

  /// icons for dashboard
  final SvgGenImage iconLink;
  final SvgGenImage iconUser;
  final SvgGenImage iconPhone;
  final SvgGenImage iconAdd;
  final SvgGenImage iconMeetingCalendar;
  final SvgGenImage iconMeetingPerson;
  final SvgGenImage iconMeetingRecurring;
  final SvgGenImage iconEdit;
  final SvgGenImage iconDelete;
  final SvgGenImage iconCopy;
  final SvgGenImage iconSorting;
  final SvgGenImage iconCheckmark;
  final SvgGenImage iconPinAngled;

  final SvgGenImage iconScheduleLogo;
  final SvgGenImage iconScheduleText;
  final SvgGenImage iconScheduleToday;
  final SvgGenImage iconScheduleTime;
  final SvgGenImage iconScheduleTimeZone;
  final SvgGenImage iconScheduleRepeat;
  final SvgGenImage iconCalendarModalHeader;
  final SvgGenImage iconDoorModalHeader;
  final SvgGenImage iconPeopleModalHeader;
  final SvgGenImage iconPersonalMeeting;

  /// icons for room logo
  final SvgGenImage logoRoomPersonal;
  final SvgGenImage logoRoomBlue;
  final SvgGenImage logoRoomGreen;
  final SvgGenImage logoRoomRed;
  final SvgGenImage logoRoomOrange;
  final SvgGenImage logoRoomPurple;

  final SvgGenImage logoScheduleBlue;
  final SvgGenImage logoScheduleGreen;
  final SvgGenImage logoScheduleRed;
  final SvgGenImage logoScheduleOrange;
  final SvgGenImage logoSchedulePurple;

  final SvgGenImage defaultRoomLogo;

  /// icons for chat
  final SvgGenImage iconChatSend;
  final SvgGenImage iconChatNoResult;
  final SvgGenImage iconChatSearch;
  final SvgGenImage iconChatLogo;

  /// icons for participant list
  final SvgGenImage iconAudioOnWave;

  /// connection quality
  final SvgGenImage iconConnectionPoor;

  /// error/warning/notice
  final SvgGenImage iconErrorMessage;
  final SvgGenImage iconWarningMessage;
  final SvgGenImage iconSecurityIndicator;
  final SvgGenImage iconLeaveMeeting;
  final SvgGenImage iconLeaveMeetingGuest;
  final SvgGenImage iconLeftMeeting;
  final SvgGenImage iconInvalidLink;
  final SvgGenImage iconValidLink;
  final SvgGenImage iconLocked;

  /// icons for early access dialog
  final SvgGenImage iconEarlyAccess;

  const ProtonImages({
    required this.protonMeetBarLogo,
    required this.iconSettings,
    required this.iconSwapCamera,
    required this.icAppNoWord,
    required this.iconClose,
    required this.iconSpeakerOn,
    required this.iconSpeakerOff,
    required this.iconSpeakerPhone,
    required this.iconReload,
    required this.iconAudioOn,
    required this.iconAudioOff,
    required this.iconVideoOn,
    required this.iconVideoOff,
    required this.iconParticipants,
    required this.iconInfo,
    required this.iconChat,
    required this.iconChatSend,
    required this.iconErrorMessage,
    required this.iconWarningMessage,
    required this.iconChatNoResult,
    required this.iconChatSearch,
    required this.iconChatLogo,
    required this.iconScreenShare,
    required this.iconEndCall,
    required this.iconSecurityIndicator,
    required this.iconLeaveMeeting,
    required this.iconLeaveMeetingGuest,
    required this.iconLeftMeeting,
    required this.iconInvalidLink,
    required this.iconLocked,
    required this.iconMore,
    required this.iconLink,
    required this.iconUser,
    required this.iconPhone,
    required this.iconAudioOnWave,
    required this.iconConnectionPoor,
    required this.iconDiamond,
    required this.iconStarShield,
    required this.iconEarlyAccess,
    required this.iconAdd,
    required this.iconMeetingCalendar,
    required this.iconMeetingPerson,
    required this.iconMeetingRecurring,
    required this.iconDeleteAccount,
    required this.iconEdit,
    required this.iconDelete,
    required this.iconCopy,
    required this.iconScheduleLogo,
    required this.iconScheduleText,
    required this.iconScheduleToday,
    required this.iconScheduleTime,
    required this.iconScheduleTimeZone,
    required this.iconScheduleRepeat,
    required this.iconCalendarModalHeader,
    required this.iconDoorModalHeader,
    required this.iconPeopleModalHeader,
    required this.logoRoomPersonal,
    required this.logoRoomBlue,
    required this.logoRoomGreen,
    required this.logoRoomRed,
    required this.logoRoomOrange,
    required this.logoRoomPurple,
    required this.logoScheduleBlue,
    required this.logoScheduleGreen,
    required this.logoScheduleRed,
    required this.logoScheduleOrange,
    required this.logoSchedulePurple,
    required this.iconPersonalMeeting,
    required this.iconSorting,
    required this.iconCheckmark,
    required this.iconPinAngled,
    required this.iconAddToCalendar,
    required this.iconUploadFile,
    required this.defaultRoomLogo,
    required this.iconValidLink,
  });

  @override
  ProtonImages copyWith({
    AssetGenImage? protonMeetBarLogo,
    SvgGenImage? iconSettings,
    SvgGenImage? iconSwapCamera,
    SvgGenImage? icAppNoWord,
    SvgGenImage? iconClose,
    SvgGenImage? iconSpeakerOn,
    SvgGenImage? iconSpeakerOff,
    SvgGenImage? iconSpeakerPhone,
    SvgGenImage? iconReload,
    SvgGenImage? iconAudioOn,
    SvgGenImage? iconAudioOff,
    SvgGenImage? iconVideoOn,
    SvgGenImage? iconVideoOff,
    SvgGenImage? iconParticipants,
    SvgGenImage? iconInfo,
    SvgGenImage? iconChat,
    SvgGenImage? iconChatSend,
    SvgGenImage? iconErrorMessage,
    SvgGenImage? iconWarningMessage,
    SvgGenImage? iconChatNoResult,
    SvgGenImage? iconChatSearch,
    SvgGenImage? iconChatLogo,
    SvgGenImage? iconScreenShare,
    SvgGenImage? iconEndCall,
    SvgGenImage? iconSecurityIndicator,
    SvgGenImage? iconLeaveMeeting,
    SvgGenImage? iconLeaveMeetingGuest,
    SvgGenImage? iconLeftMeeting,
    SvgGenImage? iconInvalidLink,
    SvgGenImage? iconLocked,
    SvgGenImage? iconMore,
    SvgGenImage? iconLink,
    SvgGenImage? iconUser,
    SvgGenImage? iconPhone,
    SvgGenImage? iconAudioOnWave,
    SvgGenImage? iconConnectionPoor,
    SvgGenImage? iconDiamond,
    SvgGenImage? iconStarShield,
    SvgGenImage? iconEarlyAccess,
    SvgGenImage? iconAdd,
    SvgGenImage? iconMeetingCalendar,
    SvgGenImage? iconMeetingPerson,
    SvgGenImage? iconMeetingRecurring,
    SvgGenImage? iconDeleteAccount,
    SvgGenImage? iconEdit,
    SvgGenImage? iconDelete,
    SvgGenImage? iconCopy,
    SvgGenImage? iconScheduleLogo,
    SvgGenImage? iconScheduleText,
    SvgGenImage? iconScheduleToday,
    SvgGenImage? iconScheduleTime,
    SvgGenImage? iconScheduleTimeZone,
    SvgGenImage? iconScheduleRepeat,
    SvgGenImage? iconCalendarModalHeader,
    SvgGenImage? iconDoorModalHeader,
    SvgGenImage? iconPeopleModalHeader,
    SvgGenImage? logoRoomPersonal,
    SvgGenImage? logoRoomBlue,
    SvgGenImage? logoRoomGreen,
    SvgGenImage? logoRoomRed,
    SvgGenImage? logoRoomOrange,
    SvgGenImage? logoRoomPurple,
    SvgGenImage? logoScheduleBlue,
    SvgGenImage? logoScheduleGreen,
    SvgGenImage? logoScheduleRed,
    SvgGenImage? logoScheduleOrange,
    SvgGenImage? logoSchedulePurple,
    SvgGenImage? iconPersonalMeeting,
    SvgGenImage? iconSorting,
    SvgGenImage? iconCheckmark,
    SvgGenImage? iconPinAngled,
    SvgGenImage? iconAddToCalendar,
    SvgGenImage? iconUploadFile,
    SvgGenImage? defaultRoomLogo,
    SvgGenImage? iconValidLink,
  }) {
    return ProtonImages(
      protonMeetBarLogo: protonMeetBarLogo ?? this.protonMeetBarLogo,
      iconSettings: iconSettings ?? this.iconSettings,
      iconSwapCamera: iconSwapCamera ?? this.iconSwapCamera,
      icAppNoWord: icAppNoWord ?? this.icAppNoWord,
      iconClose: iconClose ?? this.iconClose,
      iconSpeakerOn: iconSpeakerOn ?? this.iconSpeakerOn,
      iconSpeakerOff: iconSpeakerOff ?? this.iconSpeakerOff,
      iconSpeakerPhone: iconSpeakerPhone ?? this.iconSpeakerPhone,
      iconAudioOn: iconAudioOn ?? this.iconAudioOn,
      iconAudioOff: iconAudioOff ?? this.iconAudioOff,
      iconVideoOn: iconVideoOn ?? this.iconVideoOn,
      iconVideoOff: iconVideoOff ?? this.iconVideoOff,
      iconParticipants: iconParticipants ?? this.iconParticipants,
      iconInfo: iconInfo ?? this.iconInfo,
      iconChat: iconChat ?? this.iconChat,
      iconChatSend: iconChatSend ?? this.iconChatSend,
      iconErrorMessage: iconErrorMessage ?? this.iconErrorMessage,
      iconWarningMessage: iconWarningMessage ?? this.iconWarningMessage,
      iconChatNoResult: iconChatNoResult ?? this.iconChatNoResult,
      iconChatSearch: iconChatSearch ?? this.iconChatSearch,
      iconChatLogo: iconChatLogo ?? this.iconChatLogo,
      iconScreenShare: iconScreenShare ?? this.iconScreenShare,
      iconEndCall: iconEndCall ?? this.iconEndCall,
      iconSecurityIndicator:
          iconSecurityIndicator ?? this.iconSecurityIndicator,
      iconLeaveMeeting: iconLeaveMeeting ?? this.iconLeaveMeeting,
      iconLeaveMeetingGuest:
          iconLeaveMeetingGuest ?? this.iconLeaveMeetingGuest,
      iconLeftMeeting: iconLeftMeeting ?? this.iconLeftMeeting,
      iconInvalidLink: iconInvalidLink ?? this.iconInvalidLink,
      iconLocked: iconLocked ?? this.iconLocked,
      iconMore: iconMore ?? this.iconMore,
      iconReload: iconReload ?? this.iconReload,
      iconLink: iconLink ?? this.iconLink,
      iconUser: iconUser ?? this.iconUser,
      iconPhone: iconPhone ?? this.iconPhone,
      iconAudioOnWave: iconAudioOnWave ?? this.iconAudioOnWave,
      iconConnectionPoor: iconConnectionPoor ?? this.iconConnectionPoor,
      iconDiamond: iconDiamond ?? this.iconDiamond,
      iconStarShield: iconStarShield ?? this.iconStarShield,
      iconEarlyAccess: iconEarlyAccess ?? this.iconEarlyAccess,
      iconAdd: iconAdd ?? this.iconAdd,
      iconMeetingCalendar: iconMeetingCalendar ?? this.iconMeetingCalendar,
      iconMeetingPerson: iconMeetingPerson ?? this.iconMeetingPerson,
      iconMeetingRecurring: iconMeetingRecurring ?? this.iconMeetingRecurring,
      iconDeleteAccount: iconDeleteAccount ?? this.iconDeleteAccount,
      iconEdit: iconEdit ?? this.iconEdit,
      iconDelete: iconDelete ?? this.iconDelete,
      iconCopy: iconCopy ?? this.iconCopy,
      iconScheduleLogo: iconScheduleLogo ?? this.iconScheduleLogo,
      iconScheduleText: iconScheduleText ?? this.iconScheduleText,
      iconScheduleToday: iconScheduleToday ?? this.iconScheduleToday,
      iconScheduleTime: iconScheduleTime ?? this.iconScheduleTime,
      iconScheduleTimeZone: iconScheduleTimeZone ?? this.iconScheduleTimeZone,
      iconScheduleRepeat: iconScheduleRepeat ?? this.iconScheduleRepeat,
      iconCalendarModalHeader:
          iconCalendarModalHeader ?? this.iconCalendarModalHeader,
      iconDoorModalHeader: iconDoorModalHeader ?? this.iconDoorModalHeader,
      iconPeopleModalHeader:
          iconPeopleModalHeader ?? this.iconPeopleModalHeader,
      logoRoomPersonal: logoRoomPersonal ?? this.logoRoomPersonal,
      logoRoomBlue: logoRoomBlue ?? this.logoRoomBlue,
      logoRoomGreen: logoRoomGreen ?? this.logoRoomGreen,
      logoRoomRed: logoRoomRed ?? this.logoRoomRed,
      logoRoomOrange: logoRoomOrange ?? this.logoRoomOrange,
      logoRoomPurple: logoRoomPurple ?? this.logoRoomPurple,
      logoScheduleBlue: logoScheduleBlue ?? this.logoScheduleBlue,
      logoScheduleGreen: logoScheduleGreen ?? this.logoScheduleGreen,
      logoScheduleRed: logoScheduleRed ?? this.logoScheduleRed,
      logoScheduleOrange: logoScheduleOrange ?? this.logoScheduleOrange,
      logoSchedulePurple: logoSchedulePurple ?? this.logoSchedulePurple,
      iconPersonalMeeting: iconPersonalMeeting ?? this.iconPersonalMeeting,
      iconSorting: iconSorting ?? this.iconSorting,
      iconCheckmark: iconCheckmark ?? this.iconCheckmark,
      iconPinAngled: iconPinAngled ?? this.iconPinAngled,
      iconAddToCalendar: iconAddToCalendar ?? this.iconAddToCalendar,
      iconUploadFile: iconUploadFile ?? this.iconUploadFile,
      defaultRoomLogo: defaultRoomLogo ?? this.defaultRoomLogo,
      iconValidLink: iconValidLink ?? this.iconValidLink,
    );
  }

  @override
  ProtonImages lerp(ThemeExtension<ProtonImages>? other, double t) {
    if (other is! ProtonImages) {
      return this;
    }
    return ProtonImages(
      protonMeetBarLogo: other.protonMeetBarLogo,
      iconSettings: other.iconSettings,
      iconSwapCamera: other.iconSwapCamera,
      icAppNoWord: other.icAppNoWord,
      iconClose: other.iconClose,
      iconSpeakerOn: other.iconSpeakerOn,
      iconSpeakerOff: other.iconSpeakerOff,
      iconSpeakerPhone: other.iconSpeakerPhone,
      iconAudioOn: other.iconAudioOn,
      iconAudioOff: other.iconAudioOff,
      iconVideoOn: other.iconVideoOn,
      iconVideoOff: other.iconVideoOff,
      iconParticipants: other.iconParticipants,
      iconInfo: other.iconInfo,
      iconChat: other.iconChat,
      iconChatSend: other.iconChatSend,
      iconErrorMessage: other.iconErrorMessage,
      iconWarningMessage: other.iconWarningMessage,
      iconChatNoResult: other.iconChatNoResult,
      iconChatSearch: other.iconChatSearch,
      iconChatLogo: other.iconChatLogo,
      iconScreenShare: other.iconScreenShare,
      iconEndCall: other.iconEndCall,
      iconSecurityIndicator: other.iconSecurityIndicator,
      iconLeaveMeeting: other.iconLeaveMeeting,
      iconLeaveMeetingGuest: other.iconLeaveMeetingGuest,
      iconLeftMeeting: other.iconLeftMeeting,
      iconInvalidLink: other.iconInvalidLink,
      iconLocked: other.iconLocked,
      iconMore: other.iconMore,
      iconReload: other.iconReload,
      iconLink: other.iconLink,
      iconUser: other.iconUser,
      iconPhone: other.iconPhone,
      iconAudioOnWave: other.iconAudioOnWave,
      iconConnectionPoor: other.iconConnectionPoor,
      iconDiamond: other.iconDiamond,
      iconStarShield: other.iconStarShield,
      iconEarlyAccess: other.iconEarlyAccess,
      iconAdd: other.iconAdd,
      iconMeetingCalendar: other.iconMeetingCalendar,
      iconMeetingPerson: other.iconMeetingPerson,
      iconMeetingRecurring: other.iconMeetingRecurring,
      iconDeleteAccount: other.iconDeleteAccount,
      iconEdit: other.iconEdit,
      iconDelete: other.iconDelete,
      iconCopy: other.iconCopy,
      iconScheduleLogo: other.iconScheduleLogo,
      iconScheduleText: other.iconScheduleText,
      iconScheduleToday: other.iconScheduleToday,
      iconScheduleTime: other.iconScheduleTime,
      iconScheduleTimeZone: other.iconScheduleTimeZone,
      iconScheduleRepeat: other.iconScheduleRepeat,
      iconCalendarModalHeader: other.iconCalendarModalHeader,
      iconDoorModalHeader: other.iconDoorModalHeader,
      iconPeopleModalHeader: other.iconPeopleModalHeader,
      logoRoomPersonal: other.logoRoomPersonal,
      logoRoomBlue: other.logoRoomBlue,
      logoRoomGreen: other.logoRoomGreen,
      logoRoomRed: other.logoRoomRed,
      logoRoomOrange: other.logoRoomOrange,
      logoRoomPurple: other.logoRoomPurple,
      logoScheduleBlue: other.logoScheduleBlue,
      logoScheduleGreen: other.logoScheduleGreen,
      logoScheduleRed: other.logoScheduleRed,
      logoScheduleOrange: other.logoScheduleOrange,
      logoSchedulePurple: other.logoSchedulePurple,
      iconPersonalMeeting: other.iconPersonalMeeting,
      iconSorting: other.iconSorting,
      iconCheckmark: other.iconCheckmark,
      iconPinAngled: other.iconPinAngled,
      iconAddToCalendar: other.iconAddToCalendar,
      iconUploadFile: other.iconUploadFile,
      defaultRoomLogo: other.defaultRoomLogo,
      iconValidLink: other.iconValidLink,
    );
  }
}

final lightImageExtension = ProtonImages(
  protonMeetBarLogo: Assets.images.logos.protonMeetBarLogoClean,
  iconSettings: Assets.images.icon.icCogWheel,
  icAppNoWord: Assets.images.icon.icAppNoWord,
  iconClose: Assets.images.icon.icCross,
  iconSwapCamera: Assets.images.icon.icSwapCam,
  iconSpeakerPhone: Assets.images.icon.icSpeakerPhone,
  iconAudioOn: Assets.images.icon.icMicOn,
  iconAudioOff: Assets.images.icon.icMicOff,
  iconVideoOn: Assets.images.icon.icVideoOn,
  iconVideoOff: Assets.images.icon.icVideoOff,
  iconParticipants: Assets.images.icon.icPeople,
  iconInfo: Assets.images.icon.icInfoCircle,
  iconChat: Assets.images.icon.icChat,
  iconChatSend: Assets.images.icon.icChatSend,
  iconErrorMessage: Assets.images.icon.icWarning,
  iconWarningMessage: Assets.images.icon.icWarning,
  iconChatNoResult: Assets.images.icon.icChatNoResult,
  iconChatSearch: Assets.images.icon.icChatSearch,
  iconChatLogo: Assets.images.icon.icChatLogo,
  iconScreenShare: Assets.images.icon.icShareScreen,
  iconEndCall: Assets.images.icon.icHang,
  iconSecurityIndicator: Assets.images.icon.icSecurityIndicator,
  iconLeaveMeeting: Assets.images.icon.icMeetingShieldH,
  iconLeaveMeetingGuest: Assets.images.icon.icLeaveMeetingGuest,
  iconLeftMeeting: Assets.images.icon.icLeftMeeting,
  iconInvalidLink: Assets.images.icon.icInvalidLink,
  iconLocked: Assets.images.icon.icLocked,
  iconSpeakerOn: Assets.images.icon.icSpeakerOn,
  iconSpeakerOff: Assets.images.icon.icSpeakerOff,
  iconMore: Assets.images.icon.icMore,
  iconReload: Assets.images.icon.icReload,
  iconLink: Assets.images.icon.icLink,
  iconUser: Assets.images.icon.icUser,
  iconPhone: Assets.images.icon.icPhone,
  iconAudioOnWave: Assets.images.icon.icAudioWave,
  iconConnectionPoor: Assets.images.icon.icConnectionPoor,
  iconDiamond: Assets.images.icon.icDiamond,
  iconStarShield: Assets.images.icon.icStarShield,
  iconEarlyAccess: Assets.images.icon.icEarlyAccessDialog,
  iconAdd: Assets.images.icon.icPlus,
  iconMeetingCalendar: Assets.images.icon.icMeetingsCalendar,
  iconMeetingPerson: Assets.images.icon.icMeetingsPeople,
  iconMeetingRecurring: Assets.images.icon.icRecurring,
  iconDeleteAccount: Assets.images.icon.icTrash,
  iconEdit: Assets.images.icon.icPenSquare,
  iconDelete: Assets.images.icon.icCrossCircle,
  iconCopy: Assets.images.icon.icSquares,
  iconScheduleLogo: Assets.images.icon.icCalendarTitle,
  iconScheduleText: Assets.images.icon.icTextAlignLeft,
  iconScheduleToday: Assets.images.icon.icCalendarToday,
  iconScheduleTime: Assets.images.icon.icClock,
  iconScheduleTimeZone: Assets.images.icon.icEarth,
  iconScheduleRepeat: Assets.images.icon.icRecurring,
  iconCalendarModalHeader: Assets.images.icon.icCalendarModalHeader,
  iconDoorModalHeader: Assets.images.icon.icDoorModalHeader,
  iconPeopleModalHeader: Assets.images.icon.icPeopleModalHeader,
  logoRoomPersonal: Assets.images.logos.meetingRoomPersonal,
  logoRoomBlue: Assets.images.logos.meetingRoomBlue1,
  logoRoomGreen: Assets.images.logos.meetingRoomGreen1,
  logoRoomRed: Assets.images.logos.meetingRoomRed1,
  logoRoomOrange: Assets.images.logos.meetingRoomOrange1,
  logoRoomPurple: Assets.images.logos.meetingRoomPurple1,
  logoScheduleBlue: Assets.images.logos.meetingScheduleBlue1,
  logoScheduleGreen: Assets.images.logos.meetingScheduleGreen1,
  logoScheduleRed: Assets.images.logos.meetingScheduleRed1,
  logoScheduleOrange: Assets.images.logos.meetingScheduleOrange1,
  logoSchedulePurple: Assets.images.logos.meetingSchedulePurple1,
  iconPersonalMeeting: Assets.images.icon.icPersonalMeetingRoomAvatar,
  iconSorting: Assets.images.icon.icSort,
  iconCheckmark: Assets.images.icon.icCheckmarkStrong,
  iconPinAngled: Assets.images.icon.icPinAngled,
  iconAddToCalendar: Assets.images.icon.icSquareArrowUpRight,
  iconUploadFile: Assets.images.icon.icDataUpload,
  defaultRoomLogo: Assets.images.logos.meetingRoomPurple1,
  iconValidLink: Assets.images.icon.icValidLink,
);

final darkImageExtension = ProtonImages(
  protonMeetBarLogo: Assets.images.logos.protonMeetBarLogoClean,
  iconSettings: Assets.images.icon.icCogWheel,
  icAppNoWord: Assets.images.icon.icAppNoWord,
  iconClose: Assets.images.icon.icCross,
  iconSwapCamera: Assets.images.icon.icSwapCam,
  iconSpeakerPhone: Assets.images.icon.icSpeakerPhone,
  iconAudioOn: Assets.images.icon.icMicOn,
  iconAudioOff: Assets.images.icon.icMicOff,
  iconVideoOn: Assets.images.icon.icVideoOn,
  iconVideoOff: Assets.images.icon.icVideoOff,
  iconParticipants: Assets.images.icon.icPeople,
  iconInfo: Assets.images.icon.icInfoCircle,
  iconChat: Assets.images.icon.icChat,
  iconChatSend: Assets.images.icon.icChatSend,
  iconErrorMessage: Assets.images.icon.icWarning,
  iconWarningMessage: Assets.images.icon.icWarning,
  iconChatNoResult: Assets.images.icon.icChatNoResult,
  iconChatSearch: Assets.images.icon.icChatSearch,
  iconChatLogo: Assets.images.icon.icChatLogo,
  iconScreenShare: Assets.images.icon.icShareScreen,
  iconEndCall: Assets.images.icon.icHang,
  iconSecurityIndicator: Assets.images.icon.icSecurityIndicator,
  iconLeaveMeeting: Assets.images.icon.icEarlyAccessDialog,
  iconLeaveMeetingGuest: Assets.images.icon.icLeaveMeetingGuest,
  iconLeftMeeting: Assets.images.icon.icLeftMeeting,
  iconInvalidLink: Assets.images.icon.icInvalidLink,
  iconLocked: Assets.images.icon.icLocked,
  iconSpeakerOn: Assets.images.icon.icSpeakerOn,
  iconSpeakerOff: Assets.images.icon.icSpeakerOff,
  iconMore: Assets.images.icon.icMore,
  iconReload: Assets.images.icon.icReload,
  iconLink: Assets.images.icon.icLink,
  iconUser: Assets.images.icon.icUser,
  iconPhone: Assets.images.icon.icPhone,
  iconAudioOnWave: Assets.images.icon.icAudioWave,
  iconConnectionPoor: Assets.images.icon.icConnectionPoor,
  iconDiamond: Assets.images.icon.icDiamond,
  iconStarShield: Assets.images.icon.icStarShield,
  iconEarlyAccess: Assets.images.icon.icEarlyAccessDialog,
  iconAdd: Assets.images.icon.icPlus,
  iconMeetingCalendar: Assets.images.icon.icMeetingsCalendar,
  iconMeetingPerson: Assets.images.icon.icMeetingsPeople,
  iconMeetingRecurring: Assets.images.icon.icRecurring,
  iconDeleteAccount: Assets.images.icon.icTrash,
  iconEdit: Assets.images.icon.icPenSquare,
  iconDelete: Assets.images.icon.icCrossCircle,
  iconCopy: Assets.images.icon.icSquares,
  iconScheduleLogo: Assets.images.icon.icCalendarTitle,
  iconScheduleText: Assets.images.icon.icTextAlignLeft,
  iconScheduleToday: Assets.images.icon.icCalendarToday,
  iconScheduleTime: Assets.images.icon.icClock,
  iconScheduleTimeZone: Assets.images.icon.icEarth,
  iconScheduleRepeat: Assets.images.icon.icRecurring,
  iconCalendarModalHeader: Assets.images.icon.icCalendarModalHeader,
  iconDoorModalHeader: Assets.images.icon.icDoorModalHeader,
  iconPeopleModalHeader: Assets.images.icon.icPeopleModalHeader,
  logoRoomPersonal: Assets.images.logos.meetingRoomPersonal,
  logoRoomBlue: Assets.images.logos.meetingRoomBlue1,
  logoRoomGreen: Assets.images.logos.meetingRoomGreen1,
  logoRoomRed: Assets.images.logos.meetingRoomRed1,
  logoRoomOrange: Assets.images.logos.meetingRoomOrange1,
  logoRoomPurple: Assets.images.logos.meetingRoomPurple1,
  logoScheduleBlue: Assets.images.logos.meetingScheduleBlue1,
  logoScheduleGreen: Assets.images.logos.meetingScheduleGreen1,
  logoScheduleRed: Assets.images.logos.meetingScheduleRed1,
  logoScheduleOrange: Assets.images.logos.meetingScheduleOrange1,
  logoSchedulePurple: Assets.images.logos.meetingSchedulePurple1,
  iconPersonalMeeting: Assets.images.icon.icPersonalMeetingRoomAvatar,
  iconSorting: Assets.images.icon.icSort,
  iconCheckmark: Assets.images.icon.icCheckmarkStrong,
  iconPinAngled: Assets.images.icon.icPinAngled,
  iconAddToCalendar: Assets.images.icon.icSquareArrowUpRight,
  iconUploadFile: Assets.images.icon.icDataUpload,
  defaultRoomLogo: Assets.images.logos.meetingRoomPurple1,
  iconValidLink: Assets.images.icon.icValidLink,
);
