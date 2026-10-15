import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/constants/live_captions_constants.dart';
import 'package:meet/helper/background_blur/camera_background_selection.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/models/live_captions/live_captions_models.dart';
import 'package:meet/rust/proton_meet/models/meet_info.dart';
import 'package:meet/rust/proton_meet/models/meet_participant.dart';
import 'package:meet/rust/proton_meet/models/meeting_info.dart';
import 'package:meet/rust/proton_meet/models/mls_sync_state.dart';
import 'package:meet/rust/proton_meet/models/rejoin_reason.dart';
import 'package:meet/views/scenes/room/camera_layout.dart';
import 'package:meet/views/scenes/room/layout/responsive_camera_layout.dart'
    show ResponsiveCameraLayout;
import 'package:meet/views/scenes/room/participant/participant_info.dart';
import 'package:meet/views/scenes/room/participant_detail.dart';
import 'package:proton_denoise/proton_denoise.dart';

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

/// A pending waiting-room join request surfaced to the host from the Rust
/// `join_request` websocket event.
class WaitingRoomJoinRequest extends Equatable {
  const WaitingRoomJoinRequest({
    required this.requestId,
    required this.participantUid,
    required this.receivedAt,
    this.displayName,
    this.expiresAt,
  });

  final String requestId;
  final String participantUid;

  /// Decrypted display name from meet-server participants API, when available.
  final String? displayName;

  /// When the host received the request (used for the "Joined at" label).
  final DateTime receivedAt;

  /// Server-provided expiry, if any.
  final DateTime? expiresAt;

  /// UI label: resolved name or participant uid fallback.
  String get resolvedDisplayName {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    return participantUid;
  }

  /// Whether the server-side join request window has elapsed.
  bool get isExpired {
    final expiry = expiresAt;
    return expiry != null && !expiry.isAfter(DateTime.now());
  }

  /// Join request still within the server admission window.
  bool get isActive => !isExpired;

  @override
  List<Object?> get props => [
    requestId,
    participantUid,
    displayName,
    receivedAt,
    expiresAt,
  ];
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

  /// Pending waiting-room join requests (host only).
  final List<WaitingRoomJoinRequest> waitingRoomParticipants;

  /// Join request ids currently being admitted by the host.
  final Set<String> admittingWaitingRoomRequestIds;

  /// Join request ids currently being rejected by the host.
  final Set<String> rejectingWaitingRoomRequestIds;

  /// True while admit-all waiting-room join requests is in flight.
  final bool isAdmitAllWaitingRoomInProgress;

  /// mls group data
  final String epoch;
  final String displayCode;
  final int participantsCount;
  final int mlsGroupLen;
  final bool isPaidUser;

  /// Pre-join host hint until meet-api participant flags are available.
  final bool localHostHint;

  ///
  final int fps;
  final VideoQuality videoQuality;
  final bool hideSelfCamera;
  final CameraLayout layout;
  final int screenSharingIndex;
  final bool unsubscribeVideoByDefault;

  /// In-room preference: native camera background blur (MeetCameraBackgroundBlur).
  final bool cameraBackgroundBlurEnabled;

  /// Full camera background selection (none, blur, preset, custom image).
  final CameraBackgroundSelection cameraBackgroundSelection;

  /// In-room preference: native mic denoise (MeetAudioDenoise).
  final bool audioDenoiseEnabled;

  /// Selected denoise algorithm.
  final DenoiseType audioDenoiseType;
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

  /// Android: show notification permission inform sheet (e.g. before screen share).
  final bool shouldShowNotificationPermissionSettings;

  /// Toast when host admits a join request that is no longer pending locally.
  final bool shouldShowWaitingRoomJoinRequestNotFoundError;

  final DateTime? aloneSince;

  /// Picture-in-Picture state
  final bool isPictureInPictureActive;
  final String? pipVideoTrackSid;
  final String? pipParticipantIdentity;
  final bool isPipMode;
  final bool pipInitialized;
  final bool? pipAvailable;

  /// Remote participant identity whose camera must stay subscribed for iOS PiP
  /// when they are off the visible grid page (see [ResponsiveCameraLayout]).
  /// Empty string means none.
  final String iosPipRemoteCameraSubscriptionIdentity;

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

  /// True when headphones / headset / Bluetooth audio output is present (from device labels).
  final bool hasExternalAudioOutput;

  /// True when a Bluetooth audio output device is present (from audio session).
  final bool hasBluetoothAudioOutput;

  /// Room initialized state - true when initial setup is complete and room is ready to display
  final bool isRoomInitialized;

  /// True when participant track lists are built from the LiveKit roster at
  /// least once. Does not wait for meet-api display names ([frbParticipantsMap]).
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

  /// Whether the device has a usable network interface (Wi‑Fi / cellular / ethernet).
  /// When false, auto-rejoin and websocket reconnect are paused until connectivity returns.
  final bool isNetworkAvailable;

  /// Current device IDs - saved for rejoin device restoration
  final String? currentAudioInputDeviceId;
  final String? currentVideoInputDeviceId;
  final String? currentAudioOutputDeviceId;

  /// Identities of participants currently recording the meeting.
  ///
  /// Maintained insertion-ordered (matches the web `string[]` interface) so
  /// the banner can pick a "first" recorder deterministically.
  final List<String> participantsRecording;

  /// Local user wants live captions (`wants_captions === 'true'`).
  final bool liveCaptionsWanted;

  /// Normalized STT language for UI (`multi` when auto-detect).
  final String liveCaptionLanguage;

  /// True while a caption preference attribute write is in flight.
  final bool isLiveCaptionsPreferenceWriteInFlight;

  /// Caption bar pipeline output (step 006 wires real transcription data).
  final Transcriptions liveCaptionsTranscriptions;

  /// Bumped when any participant caption attribute changes (wanters / UI sync).
  final int liveCaptionsAttributesGeneration;

  /// One-shot flag: agent summon timed out; [RoomPage] shows a toast then clears.
  final bool shouldShowLiveCaptionsSummonFailedError;

  /// Host-controlled: whether participants may turn on live captions.
  final bool liveCaptionsAvailableForParticipants;

  /// True if anyone in the room is currently recording.
  bool get isRecordingInProgress => participantsRecording.isNotEmpty;

  /// True if [identity] is in the active recorder set.
  bool isParticipantRecording(String identity) =>
      participantsRecording.contains(identity);

  /// True when the local participant is actively recording.
  bool get isLocalParticipantRecording {
    final identity = room.localParticipant?.identity;
    return identity != null && isParticipantRecording(identity);
  }

  /// Elapsed seconds for the local recorder UI timer.
  final int localRecordingElapsedSeconds;

  /// Check if the local participant is the host/admin using API data
  /// This matches the WebApp approach which checks IsAdmin or IsHost from the backend
  bool get isHost {
    final localParticipant = room.localParticipant;
    if (localParticipant == null) return false;

    // Get participant data from state (same approach as WebApp)
    final participantData = frbParticipantsMap[localParticipant.identity];

    if (participantData == null) {
      return localHostHint;
    }

    // Check IsAdmin or IsHost (1 = Allowed, 0 or null = NotAllowed)
    // Same logic as WebApp: hasAdminPermission = !!IsAdmin || !!IsHost
    final isAdmin = participantData.isAdmin == 1;
    final isHostValue = participantData.isHost == 1;
    if (isAdmin || isHostValue) {
      return true;
    }

    // Local stub participant may exist before meet-api flags arrive.
    if (participantData.isAdmin == null && participantData.isHost == null) {
      return localHostHint;
    }

    return false;
  }

  bool get isLocalParticipantAdminOrHost => isHost;

  bool _participantIsHost(String identity) {
    final p = frbParticipantsMap[identity];
    if (p == null) return false;
    return p.isAdmin == 1 || p.isHost == 1;
  }

  bool get isOnlyHost {
    if (!isHost) return false;

    var hostCount = 0;

    final localParticipant = room.localParticipant;
    if (localParticipant != null &&
        _participantIsHost(localParticipant.identity)) {
      hostCount++;
    }

    for (final remote in room.remoteParticipants.values) {
      if (_participantIsHost(remote.identity)) {
        hostCount++;
        if (hostCount > 1) return false;
      }
    }

    return hostCount == 1;
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
    this.joinedParticipants = const [],
    this.leftParticipants = const [],
    this.waitingRoomParticipants = const [],
    this.admittingWaitingRoomRequestIds = const {},
    this.rejectingWaitingRoomRequestIds = const {},
    this.isAdmitAllWaitingRoomInProgress = false,
    this.showChatBubble = false,
    this.showParticipantList = false,
    this.isFullScreen = false,
    this.hideSelfCamera = false,
    this.isPaidUser = false,
    this.localHostHint = false,

    ///
    this.fps = 30,
    this.videoQuality = VideoQuality.HIGH,
    this.layout = CameraLayout.grid,
    this.isLocalScreenSharing = false,
    this.isRemoteScreenSharing = false,
    this.screenSharingIndex = 0,
    this.unsubscribeVideoByDefault = false,
    this.cameraBackgroundBlurEnabled = false,
    this.cameraBackgroundSelection = const CameraBackgroundSelection.none(),
    this.audioDenoiseEnabled = false,
    this.audioDenoiseType = DenoiseType.rnnoise,
    this.showMeetingIsReady = false,
    this.meetingLink = '',
    this.isSpeakerMuted,
    this.shouldShowMeetingWillEndDialog = false,
    this.shouldShowNotificationPermissionSettings = false,
    this.shouldShowWaitingRoomJoinRequestNotFoundError = false,
    this.aloneSince,
    this.isPictureInPictureActive = false,
    this.pipVideoTrackSid,
    this.pipParticipantIdentity,
    this.isPipMode = false,
    this.pipInitialized = false,
    this.pipAvailable,
    this.iosPipRemoteCameraSubscriptionIdentity = '',
    this.isCameraEnabled = false,
    this.isSpeakerPhone = false,
    this.isMeetMobileSpeakerToggleEnabled = false,
    this.meetingInfo,
    this.currentCameraPosition,
    this.audioDeviceCount = 0,
    this.hasExternalAudioOutput = false,
    this.hasBluetoothAudioOutput = false,
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
    this.isNetworkAvailable = true,
    this.currentAudioInputDeviceId,
    this.currentVideoInputDeviceId,
    this.currentAudioOutputDeviceId,
    this.participantsRecording = const [],
    this.localRecordingElapsedSeconds = 0,
    this.liveCaptionsWanted = false,
    this.liveCaptionLanguage = LiveCaptionsConstants.defaultCaptionLanguage,
    this.isLiveCaptionsPreferenceWriteInFlight = false,
    this.liveCaptionsTranscriptions = Transcriptions.empty,
    this.liveCaptionsAttributesGeneration = 0,
    this.shouldShowLiveCaptionsSummonFailedError = false,
    this.liveCaptionsAvailableForParticipants = true,
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
    List<ParticipantDetail>? joinedParticipants,
    List<ParticipantDetail>? leftParticipants,
    List<WaitingRoomJoinRequest>? waitingRoomParticipants,
    Set<String>? admittingWaitingRoomRequestIds,
    Set<String>? rejectingWaitingRoomRequestIds,
    bool? isAdmitAllWaitingRoomInProgress,
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
    bool? cameraBackgroundBlurEnabled,
    CameraBackgroundSelection? cameraBackgroundSelection,
    bool? audioDenoiseEnabled,
    DenoiseType? audioDenoiseType,
    bool? showMeetingIsReady,
    String? meetingLink,
    bool? isSpeakerMuted,
    bool? shouldShowMeetingWillEndDialog,
    bool? shouldShowNotificationPermissionSettings,
    bool? shouldShowWaitingRoomJoinRequestNotFoundError,
    DateTime? aloneSince,
    bool resetAloneStatus = false,
    bool? isPictureInPictureActive,
    String? pipVideoTrackSid,
    String? pipParticipantIdentity,
    bool? isPipMode,
    bool? pipInitialized,
    bool? pipAvailable,
    String? iosPipRemoteCameraSubscriptionIdentity,
    bool? isCameraEnabled,
    bool? isSpeakerPhone,
    bool? isMeetMobileSpeakerToggleEnabled,
    bool? isPaidUser,
    bool? localHostHint,
    FrbMeetingInfo? meetingInfo,
    CameraPosition? currentCameraPosition,
    int? audioDeviceCount,
    bool? hasExternalAudioOutput,
    bool? hasBluetoothAudioOutput,
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
    bool? isNetworkAvailable,
    String? currentAudioInputDeviceId,
    String? currentVideoInputDeviceId,
    String? currentAudioOutputDeviceId,
    List<String>? participantsRecording,
    int? localRecordingElapsedSeconds,
    bool? liveCaptionsWanted,
    String? liveCaptionLanguage,
    bool? isLiveCaptionsPreferenceWriteInFlight,
    Transcriptions? liveCaptionsTranscriptions,
    int? liveCaptionsAttributesGeneration,
    bool? shouldShowLiveCaptionsSummonFailedError,
    bool? liveCaptionsAvailableForParticipants,
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
      joinedParticipants: joinedParticipants ?? this.joinedParticipants,
      leftParticipants: leftParticipants ?? this.leftParticipants,
      waitingRoomParticipants:
          waitingRoomParticipants ?? this.waitingRoomParticipants,
      admittingWaitingRoomRequestIds:
          admittingWaitingRoomRequestIds ?? this.admittingWaitingRoomRequestIds,
      rejectingWaitingRoomRequestIds:
          rejectingWaitingRoomRequestIds ?? this.rejectingWaitingRoomRequestIds,
      isAdmitAllWaitingRoomInProgress:
          isAdmitAllWaitingRoomInProgress ??
          this.isAdmitAllWaitingRoomInProgress,
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
      cameraBackgroundBlurEnabled:
          cameraBackgroundBlurEnabled ??
          (cameraBackgroundSelection?.isEffectActive ??
              this.cameraBackgroundBlurEnabled),
      cameraBackgroundSelection:
          cameraBackgroundSelection ?? this.cameraBackgroundSelection,
      audioDenoiseEnabled: audioDenoiseEnabled ?? this.audioDenoiseEnabled,
      audioDenoiseType: audioDenoiseType ?? this.audioDenoiseType,
      meetingLink: meetingLink ?? this.meetingLink,
      showMeetingIsReady: showMeetingIsReady ?? this.showMeetingIsReady,
      isSpeakerMuted: isSpeakerMuted ?? this.isSpeakerMuted,
      shouldShowMeetingWillEndDialog:
          shouldShowMeetingWillEndDialog ?? this.shouldShowMeetingWillEndDialog,
      shouldShowNotificationPermissionSettings:
          shouldShowNotificationPermissionSettings ??
          this.shouldShowNotificationPermissionSettings,
      shouldShowWaitingRoomJoinRequestNotFoundError:
          shouldShowWaitingRoomJoinRequestNotFoundError ??
          this.shouldShowWaitingRoomJoinRequestNotFoundError,
      aloneSince: resetAloneStatus ? null : aloneSince ?? this.aloneSince,
      isPictureInPictureActive:
          isPictureInPictureActive ?? this.isPictureInPictureActive,
      pipVideoTrackSid: pipVideoTrackSid ?? this.pipVideoTrackSid,
      pipParticipantIdentity:
          pipParticipantIdentity ?? this.pipParticipantIdentity,
      isPipMode: isPipMode ?? this.isPipMode,
      pipInitialized: pipInitialized ?? this.pipInitialized,
      pipAvailable: pipAvailable ?? this.pipAvailable,
      iosPipRemoteCameraSubscriptionIdentity:
          iosPipRemoteCameraSubscriptionIdentity ??
          this.iosPipRemoteCameraSubscriptionIdentity,
      isCameraEnabled: isCameraEnabled ?? this.isCameraEnabled,
      isSpeakerPhone: isSpeakerPhone ?? this.isSpeakerPhone,
      isMeetMobileSpeakerToggleEnabled:
          isMeetMobileSpeakerToggleEnabled ??
          this.isMeetMobileSpeakerToggleEnabled,
      isPaidUser: isPaidUser ?? this.isPaidUser,
      localHostHint: localHostHint ?? this.localHostHint,
      meetingInfo: meetingInfo ?? this.meetingInfo,
      currentCameraPosition:
          currentCameraPosition ?? this.currentCameraPosition,
      audioDeviceCount: audioDeviceCount ?? this.audioDeviceCount,
      hasExternalAudioOutput:
          hasExternalAudioOutput ?? this.hasExternalAudioOutput,
      hasBluetoothAudioOutput:
          hasBluetoothAudioOutput ?? this.hasBluetoothAudioOutput,
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
      isNetworkAvailable: isNetworkAvailable ?? this.isNetworkAvailable,
      currentAudioInputDeviceId:
          currentAudioInputDeviceId ?? this.currentAudioInputDeviceId,
      currentVideoInputDeviceId:
          currentVideoInputDeviceId ?? this.currentVideoInputDeviceId,
      currentAudioOutputDeviceId:
          currentAudioOutputDeviceId ?? this.currentAudioOutputDeviceId,
      participantsRecording:
          participantsRecording ?? this.participantsRecording,
      localRecordingElapsedSeconds:
          localRecordingElapsedSeconds ?? this.localRecordingElapsedSeconds,
      liveCaptionsWanted: liveCaptionsWanted ?? this.liveCaptionsWanted,
      liveCaptionLanguage: liveCaptionLanguage ?? this.liveCaptionLanguage,
      isLiveCaptionsPreferenceWriteInFlight:
          isLiveCaptionsPreferenceWriteInFlight ??
          this.isLiveCaptionsPreferenceWriteInFlight,
      liveCaptionsTranscriptions:
          liveCaptionsTranscriptions ?? this.liveCaptionsTranscriptions,
      liveCaptionsAttributesGeneration:
          liveCaptionsAttributesGeneration ??
          this.liveCaptionsAttributesGeneration,
      shouldShowLiveCaptionsSummonFailedError:
          shouldShowLiveCaptionsSummonFailedError ??
          this.shouldShowLiveCaptionsSummonFailedError,
      liveCaptionsAvailableForParticipants:
          liveCaptionsAvailableForParticipants ??
          this.liveCaptionsAvailableForParticipants,
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
    joinedParticipants,
    leftParticipants,
    waitingRoomParticipants,
    admittingWaitingRoomRequestIds,
    rejectingWaitingRoomRequestIds,
    isAdmitAllWaitingRoomInProgress,

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
    cameraBackgroundBlurEnabled,
    cameraBackgroundSelection,
    audioDenoiseEnabled,
    audioDenoiseType,
    meetingLink,
    showMeetingIsReady,
    isSpeakerMuted,
    shouldShowMeetingWillEndDialog,
    shouldShowNotificationPermissionSettings,
    shouldShowWaitingRoomJoinRequestNotFoundError,
    aloneSince,

    ///
    isPictureInPictureActive,
    pipVideoTrackSid,
    pipParticipantIdentity,
    isPipMode,
    pipInitialized,
    pipAvailable,
    iosPipRemoteCameraSubscriptionIdentity,
    isCameraEnabled,
    isSpeakerPhone,
    isMeetMobileSpeakerToggleEnabled,
    isPaidUser,
    localHostHint,
    meetingInfo,
    currentCameraPosition,
    audioDeviceCount,
    hasExternalAudioOutput,
    hasBluetoothAudioOutput,
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
    isNetworkAvailable,
    currentAudioInputDeviceId,
    currentVideoInputDeviceId,
    currentAudioOutputDeviceId,
    participantsRecording,
    localRecordingElapsedSeconds,
    liveCaptionsWanted,
    liveCaptionLanguage,
    isLiveCaptionsPreferenceWriteInFlight,
    liveCaptionsTranscriptions,
    liveCaptionsAttributesGeneration,
    shouldShowLiveCaptionsSummonFailedError,
    liveCaptionsAvailableForParticipants,
  ];
}
