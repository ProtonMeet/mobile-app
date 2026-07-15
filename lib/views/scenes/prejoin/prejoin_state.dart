import 'package:livekit_client/livekit_client.dart';
import 'package:meet/rust/proton_meet/models/meeting_info.dart';
import 'package:meet/rust/proton_meet/models/upcoming_meeting.dart';
import 'package:meet/rust/proton_meet/user_config.dart';
import 'package:meet/views/scenes/prejoin/prejoin_arguments.dart';
import 'package:meet/views/scenes/signin/auth_bloc.dart';

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

/// Guest waiting-room admission phases on the pre-join screen.
enum WaitingRoomAdmissionPhase {
  inactive,
  hostNotStarted,
  awaitingAdmission,
}

class PreJoinState {
  final String roomName;
  final String displayName;
  final PreJoinType preJoinType;
  final bool isAudioEnabled;
  final bool isVideoEnabled;
  final bool isCameraBackgroundBlurFeatureEnabled;

  /// User toggle for the native camera background blur in the prejoin preview.
  /// Always forced to `false` when [isCameraBackgroundBlurFeatureEnabled] is `false`.
  final bool cameraBackgroundBlurEnabled;
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
  final bool hasWaitingRoom;

  /// When false, the host waiting-room toggle is hidden (gated by MeetWaitingRoom flag).
  final bool isWaitingRoomFeatureEnabled;
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
  final bool hasExternalAudioOutput;
  final bool hasBluetoothAudioOutput;
  final bool keepDisplayNameOnDevice;
  final bool
  shouldOverrideAuthDisplayName; // true if we have cached display name to override auth name
  final String? displayNameFieldError;

  /// Decrypted meeting metadata from pre-join auth; forwarded to the room.
  final FrbMeetingInfo? meetingInfo;
  final bool isMeetingHost;
  final bool isJoinAuthenticating;
  final bool shouldNavigateToWaitingRoom;

  /// Host-only: when non-null, room should sync waiting-room policy to this value on enter.
  final bool? pendingHostWaitingRoomSyncEnabled;
  final bool isPaidUser;
  final String prejoinAuthDisplayName;
  final WaitingRoomAdmissionPhase waitingRoomAdmissionPhase;
  final int waitingRoomCountdownSeconds;
  final String waitingRoomAdmissionDisplayName;
  final String waitingRoomJoinRequestId;

  static const int waitingRoomAdmissionCountdownSeconds = 300;

  final bool shouldProceedToJoinAfterHostAccept;
  final bool shouldShowJoinRequestRejectedNotification;
  final bool shouldShowWaitingRoomAdmissionTimedOutNotification;

  PreJoinState({
    this.roomName = '',
    this.displayName = '',
    this.preJoinType = PreJoinType.join,
    this.isAudioEnabled = true,
    this.isVideoEnabled = true,
    this.isCameraBackgroundBlurFeatureEnabled = false,
    this.cameraBackgroundBlurEnabled = false,
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
    this.hasWaitingRoom = false,
    this.isWaitingRoomFeatureEnabled = false,
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
    this.hasExternalAudioOutput = false,
    this.hasBluetoothAudioOutput = false,
    this.keepDisplayNameOnDevice = false,
    this.shouldOverrideAuthDisplayName = false,
    this.displayNameFieldError,
    this.meetingInfo,
    this.isMeetingHost = false,
    this.isJoinAuthenticating = false,
    this.shouldNavigateToWaitingRoom = false,
    this.pendingHostWaitingRoomSyncEnabled,
    this.isPaidUser = false,
    this.prejoinAuthDisplayName = '',
    this.waitingRoomAdmissionPhase = WaitingRoomAdmissionPhase.inactive,
    this.waitingRoomCountdownSeconds = waitingRoomAdmissionCountdownSeconds,
    this.waitingRoomAdmissionDisplayName = '',
    this.waitingRoomJoinRequestId = '',
    this.shouldProceedToJoinAfterHostAccept = false,
    this.shouldShowJoinRequestRejectedNotification = false,
    this.shouldShowWaitingRoomAdmissionTimedOutNotification = false,
  });

  PreJoinState copyWith({
    String? roomName,
    String? displayName,
    bool? isLoggingIn,
    bool? isLoggingOut,
    bool? isAudioEnabled,
    bool? isVideoEnabled,
    bool? isCameraBackgroundBlurFeatureEnabled,
    bool? cameraBackgroundBlurEnabled,
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
    bool? hasWaitingRoom,
    bool? isWaitingRoomFeatureEnabled,
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
    bool? hasExternalAudioOutput,
    bool? hasBluetoothAudioOutput,
    bool? keepDisplayNameOnDevice,
    bool? shouldOverrideAuthDisplayName,
    bool resetDisplayNameFieldError = false,
    String? displayNameFieldError,
    FrbMeetingInfo? meetingInfo,
    bool? isMeetingHost,
    bool? isJoinAuthenticating,
    bool? shouldNavigateToWaitingRoom,
    bool? pendingHostWaitingRoomSyncEnabled,
    bool resetPendingHostWaitingRoomSyncEnabled = false,
    bool? isPaidUser,
    String? prejoinAuthDisplayName,
    WaitingRoomAdmissionPhase? waitingRoomAdmissionPhase,
    int? waitingRoomCountdownSeconds,
    String? waitingRoomAdmissionDisplayName,
    String? waitingRoomJoinRequestId,
    bool? shouldProceedToJoinAfterHostAccept,
    bool? shouldShowJoinRequestRejectedNotification,
    bool? shouldShowWaitingRoomAdmissionTimedOutNotification,
  }) {
    return PreJoinState(
      roomName: roomName ?? this.roomName,
      displayName: displayName ?? this.displayName,
      preJoinType: preJoinType ?? this.preJoinType,
      isAudioEnabled: isAudioEnabled ?? this.isAudioEnabled,
      isVideoEnabled: isVideoEnabled ?? this.isVideoEnabled,
      isCameraBackgroundBlurFeatureEnabled:
          isCameraBackgroundBlurFeatureEnabled ??
          this.isCameraBackgroundBlurFeatureEnabled,
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
      hasWaitingRoom: hasWaitingRoom ?? this.hasWaitingRoom,
      isWaitingRoomFeatureEnabled:
          isWaitingRoomFeatureEnabled ?? this.isWaitingRoomFeatureEnabled,
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
      hasExternalAudioOutput:
          hasExternalAudioOutput ?? this.hasExternalAudioOutput,
      hasBluetoothAudioOutput:
          hasBluetoothAudioOutput ?? this.hasBluetoothAudioOutput,
      keepDisplayNameOnDevice:
          keepDisplayNameOnDevice ?? this.keepDisplayNameOnDevice,
      shouldOverrideAuthDisplayName:
          shouldOverrideAuthDisplayName ?? this.shouldOverrideAuthDisplayName,
      displayNameFieldError: resetDisplayNameFieldError
          ? null
          : (displayNameFieldError ?? this.displayNameFieldError),
      cameraBackgroundBlurEnabled:
          cameraBackgroundBlurEnabled ?? this.cameraBackgroundBlurEnabled,
      meetingInfo: meetingInfo ?? this.meetingInfo,
      isMeetingHost: isMeetingHost ?? this.isMeetingHost,
      isJoinAuthenticating:
          isJoinAuthenticating ?? this.isJoinAuthenticating,
      shouldNavigateToWaitingRoom:
          shouldNavigateToWaitingRoom ?? this.shouldNavigateToWaitingRoom,
      pendingHostWaitingRoomSyncEnabled: resetPendingHostWaitingRoomSyncEnabled
          ? null
          : (pendingHostWaitingRoomSyncEnabled ??
                this.pendingHostWaitingRoomSyncEnabled),
      isPaidUser: isPaidUser ?? this.isPaidUser,
      prejoinAuthDisplayName:
          prejoinAuthDisplayName ?? this.prejoinAuthDisplayName,
      waitingRoomAdmissionPhase:
          waitingRoomAdmissionPhase ?? this.waitingRoomAdmissionPhase,
      waitingRoomCountdownSeconds:
          waitingRoomCountdownSeconds ?? this.waitingRoomCountdownSeconds,
      waitingRoomAdmissionDisplayName:
          waitingRoomAdmissionDisplayName ??
          this.waitingRoomAdmissionDisplayName,
      waitingRoomJoinRequestId:
          waitingRoomJoinRequestId ?? this.waitingRoomJoinRequestId,
      shouldProceedToJoinAfterHostAccept:
          shouldProceedToJoinAfterHostAccept ??
          this.shouldProceedToJoinAfterHostAccept,
      shouldShowJoinRequestRejectedNotification:
          shouldShowJoinRequestRejectedNotification ??
          this.shouldShowJoinRequestRejectedNotification,
      shouldShowWaitingRoomAdmissionTimedOutNotification:
          shouldShowWaitingRoomAdmissionTimedOutNotification ??
          this.shouldShowWaitingRoomAdmissionTimedOutNotification,
    );
  }

  /// Builds [JoinArgs] for navigation to the join loader (WaitingRoomPage).
  JoinArgs buildJoinLoaderArgs({
    required AuthBloc authBloc,
    required String displayName,
    FrbUpcomingMeeting? meetingLink,
    bool reuseMlsJoin = false,
  }) {
    final canReusePrejoinAuth =
        meetingInfo != null &&
        prejoinAuthDisplayName.isNotEmpty &&
        displayName == prejoinAuthDisplayName;

    return JoinArgs(
      meetingLink: meetingLink ?? this.meetingLink,
      displayName: displayName,
      isVideoEnabled: isVideoEnabled,
      isAudioEnabled: isAudioEnabled,
      e2ee: enableE2EE,
      preferredCodec: videoCodec.toString(),
      authBloc: authBloc,
      role: role,
      isMeetingHost: isMeetingHost,
      waitingRoomEnabled: isMeetingHost && waitingRoomEnabled,
      prefetchedMeetingInfo: meetingInfo,
      pendingHostWaitingRoomSyncEnabled: pendingHostWaitingRoomSyncEnabled,
      prejoinAuthDisplayName: prejoinAuthDisplayName,
      reusePrejoinAuth: canReusePrejoinAuth,
      reuseMlsJoin: reuseMlsJoin,
    );
  }

  bool get isInWaitingRoomAdmission =>
      waitingRoomAdmissionPhase != WaitingRoomAdmissionPhase.inactive;

  bool get hasJoinAuthCompleted => meetingInfo != null;
}
