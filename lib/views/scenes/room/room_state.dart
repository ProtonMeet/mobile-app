import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/rust/proton_meet/models/meet_info.dart';
import 'package:meet/rust/proton_meet/models/meet_participant.dart';
import 'package:meet/rust/proton_meet/models/meeting_info.dart';
import 'package:meet/rust/proton_meet/models/mls_sync_state.dart';
import 'package:meet/rust/proton_meet/models/rejoin_reason.dart';
import 'package:meet/views/scenes/room/camera_layout.dart';
import 'package:meet/views/scenes/room/participant/participant_info.dart';
import 'package:meet/views/scenes/room/participant_detail.dart';

/// Rejoin status enum for tracking rejoin process steps
enum RejoinStatus {
  preparing,
  reconnecting,
  joining,
  updatingAccessToken,
  settingUpEncryption,
  creatingRoomConnection,
  connectingToRoom,
  finalizingConnection,
  republishingTracks,
  error;

  /// Get display message for the rejoin status
  String displayMessage(BuildContext context) {
    switch (this) {
      default:
        return context.local.trying_to_reconnect;
      // case RejoinStatus.preparing:
      //   return 'Preparing to rejoin...';
      // case RejoinStatus.reconnecting:
      //   return 'Reconnecting to meeting...';
      // case RejoinStatus.joining:
      //   return 'Joining meeting...';
      // case RejoinStatus.updatingAccessToken:
      //   return 'Updating access token...';
      // case RejoinStatus.settingUpEncryption:
      //   return 'Setting up encryption...';
      // case RejoinStatus.creatingRoomConnection:
      //   return 'Creating room connection...';
      // case RejoinStatus.connectingToRoom:
      //   return 'Connecting to room...';
      // case RejoinStatus.finalizingConnection:
      //   return 'Finalizing connection...';
      // case RejoinStatus.republishingTracks:
      //   return 'Restoring audio and video...';
      // case RejoinStatus.error:
      //   return 'Failed to rejoin meeting';
    }
  }
}

class RoomState extends Equatable {
  /// livekit room instance, it will be passed in from the waitting room
  final Room room;

  /// livekit room listener.
  final EventsListener<RoomEvent> listener;

  /// meet info
  final FrbMeetInfo meetInfo;

  /// display name
  final String displayName;

  /// room participants
  final Map<String, MeetParticipant> frbParticipantsMap;

  /// joined participants
  final List<ParticipantDetail> joinedParticipants;
  final List<ParticipantDetail> leftParticipants;

  /// messages
  final List<types.Message> messages;

  /// mls group data
  final String epoch;
  final String displayCode;
  final int participantsCount;
  final int mlsGroupLen;
  final bool isPaidUser;

  ///
  final int fps;
  final VideoQuality videoQuality;
  final bool hideSelfCamera;
  final CameraLayout layout;
  final int screenSharingIndex;
  final bool unsubscribeVideoByDefault;
  final CameraPosition? currentCameraPosition;

  /// is screen sharing
  final bool isLocalScreenSharing;
  final bool isRemoteScreenSharing;

  ///
  final String? roomKey;
  final List<ParticipantInfo> participantTracks;
  final List<ParticipantInfo> screenSharingTracks;
  final List<ParticipantInfo> speakerTracks;
  final Map<String, bool> raisedHandsByIdentity;

  /// show chat bubble
  final bool showChatBubble;

  /// show participant list
  final bool showParticipantList;

  /// is full screen
  final bool isFullScreen;

  final bool showMeetingIsReady;
  final String meetingLink;
  final bool? isSpeakerMuted;

  /// Alone meeting tracking
  final bool shouldShowMeetingWillEndDialog;
  final DateTime? aloneSince;

  /// Picture-in-Picture state
  final bool isPictureInPictureActive;
  final String? pipVideoTrackSid;
  final String? pipParticipantIdentity;
  final bool isPipMode;
  final bool pipInitialized;
  final bool? pipAvailable;

  /// Camera enabled state for local participant
  final bool isCameraEnabled;

  /// Speakerphone enabled state (Android only for now)
  final bool isSpeakerPhone;

  /// Mobile Speaker Toggle feature flag enabled state
  final bool isMeetMobileSpeakerToggleEnabled;

  /// Meeting info from appCore.getMeetingInfo
  final FrbMeetingInfo? meetingInfo;

  /// Audio device count for tracking audio device changes
  final int audioDeviceCount;

  /// Room initialized state - true when initial setup is complete and room is ready to display
  final bool isRoomInitialized;

  /// Track initialized state - true when tracks are initialized and ready
  final bool isTrackInitialized;

  /// Rejoining state - true when room is being rejoined after connection loss
  final bool isRejoining;

  /// Rejoin status - shows current step of rejoin process
  final RejoinStatus? rejoinStatus;

  /// Rejoin error message - shows error if rejoin failed
  final String? rejoinError;

  /// Rejoin failed count - tracks number of failed rejoin attempts
  final int rejoinFailedCount;

  /// Rejoin completed timestamp - tracks when rejoin was last completed
  /// Used to prevent immediate rejoin trigger after completion
  final DateTime? rejoinCompletedAt;

  /// Total rejoin count - tracks total number of rejoin attempts (including successful and failed)
  final int rejoinCount;

  /// Rejoin started timestamp - tracks when current rejoin attempt started
  /// Used to calculate rejoin duration for metrics
  final DateTime? rejoinStartedAt;

  /// Current rejoin reason - tracks why rejoin was triggered
  final RejoinReason? rejoinReason;

  /// MLS sync state - current synchronization state of MLS
  final MlsSyncState? mlsSyncState;

  /// Force show connection status banner - if true, banner will always be shown regardless of connection state
  final bool forceShowConnectionStatusBanner;

  /// Whether the rejoin failed dialog is currently showing
  final bool isRejoinFailedDialogShowing;

  /// LiveKit room reconnecting state - true when LiveKit is reconnecting (not our custom rejoin)
  final bool isLiveKitReconnecting;

  /// Current device IDs - saved for rejoin device restoration
  final String? currentAudioInputDeviceId;
  final String? currentVideoInputDeviceId;
  final String? currentAudioOutputDeviceId;

  /// Check if the local participant is the host/admin using API data
  /// This matches the WebApp approach which checks IsAdmin or IsHost from the backend
  bool get isHost {
    final localParticipant = room.localParticipant;
    if (localParticipant == null) return false;

    // Get participant data from state (same approach as WebApp)
    final participantData = frbParticipantsMap[localParticipant.identity];

    if (participantData == null) {
      // If participant data not yet loaded, fallback to checking if alone
      final remoteParticipants = room.remoteParticipants.values.toList();
      return remoteParticipants.isEmpty;
    }

    // Check IsAdmin or IsHost (1 = Allowed, 0 or null = NotAllowed)
    // Same logic as WebApp: hasAdminPermission = !!IsAdmin || !!IsHost
    final isAdmin = participantData.isAdmin == 1;
    final isHostValue = participantData.isHost == 1;

    return isAdmin || isHostValue;
  }

  const RoomState({
    required this.room,
    required this.listener,
    required this.meetInfo,
    this.displayName = '',
    this.frbParticipantsMap = const {},
    this.roomKey,
    this.epoch = '',
    this.displayCode = '',
    this.participantsCount = 0,
    this.mlsGroupLen = 0,
    this.participantTracks = const [],
    this.screenSharingTracks = const [],
    this.speakerTracks = const [],
    this.raisedHandsByIdentity = const {},
    this.messages = const [],
    this.joinedParticipants = const [],
    this.leftParticipants = const [],
    this.showChatBubble = false,
    this.showParticipantList = false,
    this.isFullScreen = false,
    this.hideSelfCamera = false,
    this.isPaidUser = false,

    ///
    this.fps = 30,
    this.videoQuality = VideoQuality.HIGH,
    this.layout = CameraLayout.grid,
    this.isLocalScreenSharing = false,
    this.isRemoteScreenSharing = false,
    this.screenSharingIndex = 0,
    this.unsubscribeVideoByDefault = false,
    this.showMeetingIsReady = false,
    this.meetingLink = '',
    this.isSpeakerMuted,
    this.shouldShowMeetingWillEndDialog = false,
    this.aloneSince,
    this.isPictureInPictureActive = false,
    this.pipVideoTrackSid,
    this.pipParticipantIdentity,
    this.isPipMode = false,
    this.pipInitialized = false,
    this.pipAvailable,
    this.isCameraEnabled = false,
    this.isSpeakerPhone = false,
    this.isMeetMobileSpeakerToggleEnabled = false,
    this.meetingInfo,
    this.currentCameraPosition,
    this.audioDeviceCount = 0,
    this.isRoomInitialized = false,
    this.isTrackInitialized = false,
    this.isRejoining = false,
    this.rejoinStatus,
    this.rejoinError,
    this.rejoinFailedCount = 0,
    this.rejoinCompletedAt,
    this.rejoinCount = 0,
    this.rejoinStartedAt,
    this.rejoinReason,
    this.mlsSyncState,
    this.forceShowConnectionStatusBanner = false,
    this.isRejoinFailedDialogShowing = false,
    this.isLiveKitReconnecting = false,
    this.currentAudioInputDeviceId,
    this.currentVideoInputDeviceId,
    this.currentAudioOutputDeviceId,
  });

  RoomState copyWith({
    String? displayName,
    String? roomKey,
    String? epoch,
    String? displayCode,
    int? participantsCount,
    int? mlsGroupLen,
    Map<String, MeetParticipant>? frbParticipantsMap,
    List<ParticipantInfo>? participantTracks,
    List<ParticipantInfo>? screenSharingTracks,
    List<ParticipantInfo>? speakerTracks,
    Map<String, bool>? raisedHandsByIdentity,
    List<types.Message>? messages,
    List<ParticipantDetail>? joinedParticipants,
    List<ParticipantDetail>? leftParticipants,
    bool? showChatBubble,
    bool? showParticipantList,
    bool? isFullScreen,
    bool? hideSelfCamera,
    int? fps,
    VideoQuality? videoQuality,
    CameraLayout? layout,
    bool? isLocalScreenSharing,
    bool? isRemoteScreenSharing,
    int? screenSharingIndex,
    bool? unsubscribeVideoByDefault,
    DateTime? lastOpenChatTime,
    bool? showMeetingIsReady,
    String? meetingLink,
    bool? isSpeakerMuted,
    bool? shouldShowMeetingWillEndDialog,
    DateTime? aloneSince,
    bool resetAloneStatus = false,
    bool? isPictureInPictureActive,
    String? pipVideoTrackSid,
    String? pipParticipantIdentity,
    bool? isPipMode,
    bool? pipInitialized,
    bool? pipAvailable,
    bool? isCameraEnabled,
    bool? isSpeakerPhone,
    bool? isMeetMobileSpeakerToggleEnabled,
    bool? isPaidUser,
    FrbMeetingInfo? meetingInfo,
    CameraPosition? currentCameraPosition,
    int? audioDeviceCount,
    bool? isRoomInitialized,
    bool? isTrackInitialized,
    bool? isRejoining,
    RejoinStatus? rejoinStatus,
    String? rejoinError,
    int? rejoinFailedCount,
    DateTime? rejoinCompletedAt,
    int? rejoinCount,
    DateTime? rejoinStartedAt,
    RejoinReason? rejoinReason,
    MlsSyncState? mlsSyncState,
    bool? forceShowConnectionStatusBanner,
    bool? isRejoinFailedDialogShowing,
    bool? isLiveKitReconnecting,
    String? currentAudioInputDeviceId,
    String? currentVideoInputDeviceId,
    String? currentAudioOutputDeviceId,
  }) {
    return RoomState(
      room: room,
      listener: listener,
      meetInfo: meetInfo,
      displayName: displayName ?? this.displayName,
      roomKey: roomKey ?? this.roomKey,
      epoch: epoch ?? this.epoch,
      displayCode: displayCode ?? this.displayCode,
      participantsCount: participantsCount ?? this.participantsCount,
      mlsGroupLen: mlsGroupLen ?? this.mlsGroupLen,
      frbParticipantsMap: frbParticipantsMap ?? this.frbParticipantsMap,
      participantTracks: participantTracks ?? this.participantTracks,
      screenSharingTracks: screenSharingTracks ?? this.screenSharingTracks,
      speakerTracks: speakerTracks ?? this.speakerTracks,
      raisedHandsByIdentity:
          raisedHandsByIdentity ?? this.raisedHandsByIdentity,
      messages: messages ?? this.messages,
      joinedParticipants: joinedParticipants ?? this.joinedParticipants,
      leftParticipants: leftParticipants ?? this.leftParticipants,
      showChatBubble: showChatBubble ?? this.showChatBubble,
      showParticipantList: showParticipantList ?? this.showParticipantList,
      isFullScreen: isFullScreen ?? this.isFullScreen,
      isLocalScreenSharing: isLocalScreenSharing ?? this.isLocalScreenSharing,
      isRemoteScreenSharing:
          isRemoteScreenSharing ?? this.isRemoteScreenSharing,
      hideSelfCamera: hideSelfCamera ?? this.hideSelfCamera,
      fps: fps ?? this.fps,
      videoQuality: videoQuality ?? this.videoQuality,
      layout: layout ?? this.layout,
      screenSharingIndex: screenSharingIndex ?? this.screenSharingIndex,
      unsubscribeVideoByDefault:
          unsubscribeVideoByDefault ?? this.unsubscribeVideoByDefault,
      meetingLink: meetingLink ?? this.meetingLink,
      showMeetingIsReady: showMeetingIsReady ?? this.showMeetingIsReady,
      isSpeakerMuted: isSpeakerMuted ?? this.isSpeakerMuted,
      shouldShowMeetingWillEndDialog:
          shouldShowMeetingWillEndDialog ?? this.shouldShowMeetingWillEndDialog,
      aloneSince: resetAloneStatus ? null : aloneSince ?? this.aloneSince,
      isPictureInPictureActive:
          isPictureInPictureActive ?? this.isPictureInPictureActive,
      pipVideoTrackSid: pipVideoTrackSid ?? this.pipVideoTrackSid,
      pipParticipantIdentity:
          pipParticipantIdentity ?? this.pipParticipantIdentity,
      isPipMode: isPipMode ?? this.isPipMode,
      pipInitialized: pipInitialized ?? this.pipInitialized,
      pipAvailable: pipAvailable ?? this.pipAvailable,
      isCameraEnabled: isCameraEnabled ?? this.isCameraEnabled,
      isSpeakerPhone: isSpeakerPhone ?? this.isSpeakerPhone,
      isMeetMobileSpeakerToggleEnabled:
          isMeetMobileSpeakerToggleEnabled ??
          this.isMeetMobileSpeakerToggleEnabled,
      isPaidUser: isPaidUser ?? this.isPaidUser,
      meetingInfo: meetingInfo ?? this.meetingInfo,
      currentCameraPosition:
          currentCameraPosition ?? this.currentCameraPosition,
      audioDeviceCount: audioDeviceCount ?? this.audioDeviceCount,
      isRoomInitialized: isRoomInitialized ?? this.isRoomInitialized,
      isTrackInitialized: isTrackInitialized ?? this.isTrackInitialized,
      isRejoining: isRejoining ?? this.isRejoining,
      rejoinStatus: rejoinStatus ?? this.rejoinStatus,
      rejoinError: rejoinError ?? this.rejoinError,
      rejoinFailedCount: rejoinFailedCount ?? this.rejoinFailedCount,
      rejoinCompletedAt: rejoinCompletedAt ?? this.rejoinCompletedAt,
      rejoinCount: rejoinCount ?? this.rejoinCount,
      rejoinStartedAt: rejoinStartedAt ?? this.rejoinStartedAt,
      rejoinReason: rejoinReason ?? this.rejoinReason,
      mlsSyncState: mlsSyncState ?? this.mlsSyncState,
      forceShowConnectionStatusBanner:
          forceShowConnectionStatusBanner ??
          this.forceShowConnectionStatusBanner,
      isRejoinFailedDialogShowing:
          isRejoinFailedDialogShowing ?? this.isRejoinFailedDialogShowing,
      isLiveKitReconnecting:
          isLiveKitReconnecting ?? this.isLiveKitReconnecting,
      currentAudioInputDeviceId:
          currentAudioInputDeviceId ?? this.currentAudioInputDeviceId,
      currentVideoInputDeviceId:
          currentVideoInputDeviceId ?? this.currentVideoInputDeviceId,
      currentAudioOutputDeviceId:
          currentAudioOutputDeviceId ?? this.currentAudioOutputDeviceId,
    );
  }

  @override
  List<Object?> get props => [
    room,
    listener,
    meetInfo,
    displayName,
    frbParticipantsMap,
    epoch,
    displayCode,
    roomKey,
    participantsCount,
    mlsGroupLen,
    participantTracks,
    screenSharingTracks,
    speakerTracks,
    raisedHandsByIdentity,
    messages,

    joinedParticipants,
    leftParticipants,

    showChatBubble,
    showParticipantList,
    isFullScreen,

    ///
    isLocalScreenSharing,
    isRemoteScreenSharing,
    hideSelfCamera,
    fps,
    videoQuality,
    layout,
    screenSharingIndex,
    unsubscribeVideoByDefault,
    meetingLink,
    showMeetingIsReady,
    isSpeakerMuted,
    shouldShowMeetingWillEndDialog,
    aloneSince,

    ///
    isPictureInPictureActive,
    pipVideoTrackSid,
    pipParticipantIdentity,
    isPipMode,
    pipInitialized,
    pipAvailable,
    isCameraEnabled,
    isSpeakerPhone,
    isMeetMobileSpeakerToggleEnabled,
    isPaidUser,
    meetingInfo,
    currentCameraPosition,
    audioDeviceCount,
    isRoomInitialized,
    isTrackInitialized,
    isRejoining,
    rejoinStatus,
    rejoinError,
    rejoinFailedCount,
    rejoinCompletedAt,
    rejoinCount,
    rejoinStartedAt,
    rejoinReason,
    mlsSyncState,
    forceShowConnectionStatusBanner,
    isRejoinFailedDialogShowing,
    isLiveKitReconnecting,
    currentAudioInputDeviceId,
    currentVideoInputDeviceId,
    currentAudioOutputDeviceId,
  ];
}
