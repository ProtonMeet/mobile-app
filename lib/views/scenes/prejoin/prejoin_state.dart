import 'package:livekit_client/livekit_client.dart';
import 'package:meet/rust/proton_meet/models/upcoming_meeting.dart';
import 'package:meet/rust/proton_meet/user_config.dart';
import 'package:meet/views/scenes/prejoin/prejoin_arguments.dart';

enum VideoCodec {
  av1,
  vp8,
  vp9,
  h264;

  @override
  String toString() {
    switch (this) {
      case VideoCodec.av1:
        return 'AV1';
      case VideoCodec.vp8:
        return 'VP8';
      case VideoCodec.vp9:
        return 'VP9';
      case VideoCodec.h264:
        return 'H264';
    }
  }

  String get lowerCase {
    return toString().toLowerCase();
  }
}

class PreJoinState {
  final String roomName;
  final String displayName;
  final PreJoinType preJoinType;
  final bool isAudioEnabled;
  final bool isVideoEnabled;
  final bool isCameraPermissionGranted;
  final bool isMicrophonePermissionGranted;
  final bool shouldShowCameraPermissionSettings;
  final bool shouldShowMicrophonePermissionSettings;
  final bool isE2EEEnabled;
  final bool enableE2EE;
  final MediaDevice? selectedVideoDevice;
  final MediaDevice? selectedAudioDevice;
  final MediaDevice? selectedSpeakerDevice;
  final CameraPosition? selectedVideoPosition;
  final VideoParameters selectedVideoParameters;
  final List<MediaDevice> videoDevices;
  final List<MediaDevice> audioDevices;
  final List<MediaDevice> speakerDevices;
  final bool isLoading;
  final String? error;
  final PrejoinRole role;
  final bool waitingRoomEnabled;
  final bool meetingPasswordEnabled;
  final String meetingPasswordValue;
  final LocalAudioTrack? audioTrack;
  final LocalVideoTrack? videoTrack;
  final VideoCodec videoCodec;
  final UserConfig? userConfig;
  final String versionDisplay;
  final bool isPermissionGranted;
  final bool isSignedOut;
  final FrbUpcomingMeeting? meetingLink;
  final String? meetingLinkUrl;
  final bool isSpeakerPhoneEnabled;
  final bool isMeetMobileSpeakerToggleEnabled;
  final bool keepDisplayNameOnDevice;
  final bool
  shouldOverrideAuthDisplayName; // true if we have cached display name to override auth name

  PreJoinState({
    this.roomName = '',
    this.displayName = '',
    this.preJoinType = PreJoinType.join,
    this.isAudioEnabled = true,
    this.isVideoEnabled = true,
    this.isCameraPermissionGranted = false,
    this.isMicrophonePermissionGranted = false,
    this.shouldShowCameraPermissionSettings = false,
    this.shouldShowMicrophonePermissionSettings = false,
    this.isE2EEEnabled = false,
    this.enableE2EE = false,
    this.selectedVideoDevice,
    this.selectedAudioDevice,
    this.selectedSpeakerDevice,
    this.selectedVideoParameters = VideoParametersPresets.h720_169,
    this.selectedVideoPosition,
    this.videoDevices = const [],
    this.audioDevices = const [],
    this.speakerDevices = const [],
    this.isLoading = false,
    this.error,
    this.role = PrejoinRole.guest,
    this.waitingRoomEnabled = false,
    this.meetingPasswordEnabled = false,
    this.meetingPasswordValue = '',
    this.audioTrack,
    this.videoTrack,
    // Default to H264, will be set by unleash flag
    this.videoCodec = VideoCodec.vp8,
    this.userConfig,
    this.versionDisplay = '',
    this.isPermissionGranted = false,
    this.isSignedOut = false,
    this.meetingLink,
    this.meetingLinkUrl,
    this.isSpeakerPhoneEnabled = false,
    this.isMeetMobileSpeakerToggleEnabled = false,
    this.keepDisplayNameOnDevice = false,
    this.shouldOverrideAuthDisplayName = false,
  });

  PreJoinState copyWith({
    String? roomName,
    String? displayName,
    bool? isLoggingIn,
    bool? isLoggingOut,
    bool? isAudioEnabled,
    bool? isVideoEnabled,
    bool? isCameraPermissionGranted,
    bool? isMicrophonePermissionGranted,
    bool? shouldShowCameraPermissionSettings,
    bool? shouldShowMicrophonePermissionSettings,
    bool? isE2EEEnabled,
    bool? enableE2EE,
    MediaDevice? selectedVideoDevice,
    MediaDevice? selectedAudioDevice,
    MediaDevice? selectedSpeakerDevice,
    CameraPosition? selectedVideoPosition,
    VideoParameters? selectedVideoParameters,
    List<MediaDevice>? videoDevices,
    List<MediaDevice>? audioDevices,
    List<MediaDevice>? speakerDevices,
    bool? isLoading,
    String? error,
    PrejoinRole? role,
    bool? waitingRoomEnabled,
    bool? meetingPasswordEnabled,
    String? meetingPasswordValue,
    LocalAudioTrack? audioTrack,
    LocalVideoTrack? videoTrack,
    VideoCodec? videoCodec,
    UserConfig? userConfig,
    String? versionDisplay,
    bool? isPermissionGranted,
    bool isSignedOut = false,
    FrbUpcomingMeeting? meetingLink,
    String? meetingLinkUrl,
    PreJoinType? preJoinType,
    bool? isSpeakerPhoneEnabled,
    bool? isMeetMobileSpeakerToggleEnabled,
    bool? keepDisplayNameOnDevice,
    bool? shouldOverrideAuthDisplayName,
  }) {
    return PreJoinState(
      roomName: roomName ?? this.roomName,
      displayName: displayName ?? this.displayName,
      preJoinType: preJoinType ?? this.preJoinType,
      isAudioEnabled: isAudioEnabled ?? this.isAudioEnabled,
      isVideoEnabled: isVideoEnabled ?? this.isVideoEnabled,
      shouldShowCameraPermissionSettings:
          shouldShowCameraPermissionSettings ??
          this.shouldShowCameraPermissionSettings,
      shouldShowMicrophonePermissionSettings:
          shouldShowMicrophonePermissionSettings ??
          this.shouldShowMicrophonePermissionSettings,
      isE2EEEnabled: isE2EEEnabled ?? this.isE2EEEnabled,
      enableE2EE: enableE2EE ?? this.enableE2EE,
      selectedVideoDevice: selectedVideoDevice ?? this.selectedVideoDevice,
      selectedAudioDevice: selectedAudioDevice ?? this.selectedAudioDevice,
      selectedSpeakerDevice:
          selectedSpeakerDevice ?? this.selectedSpeakerDevice,
      selectedVideoParameters:
          selectedVideoParameters ?? this.selectedVideoParameters,
      videoDevices: videoDevices ?? this.videoDevices,
      audioDevices: audioDevices ?? this.audioDevices,
      speakerDevices: speakerDevices ?? this.speakerDevices,
      selectedVideoPosition:
          selectedVideoPosition ?? this.selectedVideoPosition,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      role: role ?? this.role,
      waitingRoomEnabled: waitingRoomEnabled ?? this.waitingRoomEnabled,
      meetingPasswordEnabled:
          meetingPasswordEnabled ?? this.meetingPasswordEnabled,
      meetingPasswordValue: meetingPasswordValue ?? this.meetingPasswordValue,
      audioTrack: audioTrack ?? this.audioTrack,
      videoTrack: videoTrack ?? this.videoTrack,
      videoCodec: videoCodec ?? this.videoCodec,
      userConfig: userConfig ?? this.userConfig,
      versionDisplay: versionDisplay ?? this.versionDisplay,
      isPermissionGranted: isPermissionGranted ?? this.isPermissionGranted,
      isCameraPermissionGranted:
          isCameraPermissionGranted ?? this.isCameraPermissionGranted,
      isMicrophonePermissionGranted:
          isMicrophonePermissionGranted ?? this.isMicrophonePermissionGranted,
      meetingLink: meetingLink ?? this.meetingLink,
      meetingLinkUrl: meetingLinkUrl ?? this.meetingLinkUrl,
      isSpeakerPhoneEnabled:
          isSpeakerPhoneEnabled ?? this.isSpeakerPhoneEnabled,
      isMeetMobileSpeakerToggleEnabled:
          isMeetMobileSpeakerToggleEnabled ??
          this.isMeetMobileSpeakerToggleEnabled,
      keepDisplayNameOnDevice:
          keepDisplayNameOnDevice ?? this.keepDisplayNameOnDevice,
      shouldOverrideAuthDisplayName:
          shouldOverrideAuthDisplayName ?? this.shouldOverrideAuthDisplayName,
    );
  }
}
