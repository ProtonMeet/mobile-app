import 'package:equatable/equatable.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:logger/logger.dart';
import 'package:meet/helper/background_blur/camera_background_blur_sync.dart'
    show syncLocalCameraBackgroundEffect;
import 'package:meet/helper/background_blur/camera_background_selection.dart';
import 'package:meet/rust/proton_meet/models/meeting_info.dart';
import 'package:meet/rust/proton_meet/models/mls_sync_state.dart';
import 'package:meet/rust/proton_meet/models/rejoin_reason.dart';
import 'package:meet/rust/proton_meet/models/upcoming_meeting.dart';
import 'package:meet/views/scenes/prejoin/prejoin_arguments.dart';
import 'package:meet/views/scenes/room/chat/chat_models.dart';
import 'package:meet/views/scenes/room/participant_track.dart';
import 'package:meet/views/scenes/room/room_state.dart';
import 'package:proton_denoise/proton_denoise.dart';

abstract class RoomBlocEvent extends Equatable {
  const RoomBlocEvent();

  @override
  List<Object?> get props => [];
}

class RoomInitialized extends RoomBlocEvent {
  final Room room;
  final EventsListener<RoomEvent> listener;
  final String roomKey;
  final String meetLinkName;
  final String displayName;
  final PreJoinType preJoinType;
  final FrbUpcomingMeeting meetingLink;

  /// User preference for camera background blur carried over from the prejoin
  /// screen. The bloc still gates the actual attach through the feature flag
  /// and the published track lookup in [syncLocalCameraBackgroundEffect].
  final bool cameraBackgroundBlurEnabled;

  /// Full background selection (blur, preset, or custom image) from prejoin.
  final CameraBackgroundSelection cameraBackgroundSelection;

  /// Populated during pre-join to skip a redundant getMeetingInfo call.
  final FrbMeetingInfo? prefetchedMeetingInfo;

  const RoomInitialized({
    required this.room,
    required this.listener,
    required this.roomKey,
    required this.meetLinkName,
    required this.displayName,
    required this.preJoinType,
    required this.meetingLink,
    this.cameraBackgroundBlurEnabled = false,
    this.cameraBackgroundSelection = const CameraBackgroundSelection.none(),
    this.prefetchedMeetingInfo,
  });

  @override
  List<Object?> get props => [
    room,
    listener,
    roomKey,
    meetLinkName,
    displayName,
    preJoinType,
    meetingLink,
    cameraBackgroundBlurEnabled,
    cameraBackgroundSelection,
    prefetchedMeetingInfo,
  ];
}

class SortParticipants extends RoomBlocEvent {
  @override
  List<Object?> get props => [];
}

/// Debounced version of SortParticipants for high-frequency events
/// to reduce excessive sorting with large participant counts
class DebouncedSortParticipants extends RoomBlocEvent {
  @override
  List<Object?> get props => [];
}

class AddSystemMessage extends RoomBlocEvent {
  final String message;
  final String identity;
  final String name;
  final String type;

  final Level logLevel;

  final ChatJoinLeaveKind? joinLeaveKind;
  final String? meetingName;

  const AddSystemMessage(
    this.message,
    this.identity,
    this.name, {
    this.logLevel = Level.debug,
    this.type = 'system',
    this.joinLeaveKind,
    this.meetingName,
  });

  @override
  List<Object?> get props => [
    message,
    identity,
    name,
    joinLeaveKind,
    meetingName,
  ];
}

class SendChatMessage extends RoomBlocEvent {
  const SendChatMessage({
    required this.text,
    required this.localDisplayName,
    this.replyToId,
    this.topicId,
  });

  final String text;
  final String localDisplayName;
  final String? replyToId;
  final String? topicId;

  @override
  List<Object?> get props => [text, localDisplayName, replyToId, topicId];
}

class ToggleChatReaction extends RoomBlocEvent {
  const ToggleChatReaction({
    required this.messageId,
    required this.emoji,
    this.existingReactionId,
  });

  final String messageId;
  final String emoji;

  /// When set, the local participant is removing an existing reaction.
  final String? existingReactionId;

  @override
  List<Object?> get props => [messageId, emoji, existingReactionId];
}

class ReceiveChatTextMessage extends RoomBlocEvent {
  const ReceiveChatTextMessage({
    required this.id,
    required this.message,
    required this.timestamp,
    required this.identity,
    required this.name,
    this.showToast = false,
  });

  final String id;
  final String message;
  final int timestamp;
  final String identity;
  final String name;
  final bool showToast;

  @override
  List<Object?> get props => [
    id,
    message,
    timestamp,
    identity,
    name,
    showToast,
  ];
}

class ReceiveMimiChatMessage extends RoomBlocEvent {
  const ReceiveMimiChatMessage({
    required this.id,
    required this.message,
    required this.timestamp,
    required this.identity,
    required this.name,
    this.inReplyToId,
    this.topicId,
    this.showToast = false,
  });

  final String id;
  final String message;
  final int timestamp;
  final String identity;
  final String name;
  final String? inReplyToId;
  final String? topicId;
  final bool showToast;

  @override
  List<Object?> get props => [
    id,
    message,
    timestamp,
    identity,
    name,
    inReplyToId,
    topicId,
    showToast,
  ];
}

class ReceiveMimiChatReaction extends RoomBlocEvent {
  const ReceiveMimiChatReaction({
    required this.reactionId,
    required this.senderIdentity,
    this.replacesId,
    this.targetId,
    this.emoji,
  });

  final String reactionId;
  final String senderIdentity;
  final String? replacesId;
  final String? targetId;
  final String? emoji;

  @override
  List<Object?> get props => [
    reactionId,
    senderIdentity,
    replacesId,
    targetId,
    emoji,
  ];
}

class RemoveChatMessage extends RoomBlocEvent {
  const RemoveChatMessage(this.messageId);

  final String messageId;

  @override
  List<Object?> get props => [messageId];
}

/// room events
class RoomDisposed extends RoomBlocEvent {}

class ToggleFullScreen extends RoomBlocEvent {}

class StartAutoFullScreenTimer extends RoomBlocEvent {}

class ResetAutoFullScreenTimer extends RoomBlocEvent {}

class ToggleChatBubble extends RoomBlocEvent {}

class ToggleParticipantList extends RoomBlocEvent {}

/// A new waiting-room join request arrived (host only). Forwarded from the
/// Rust `join_request` websocket event via the AppCore callback.
class WaitingRoomJoinRequestReceived extends RoomBlocEvent {
  final String requestId;
  final String participantUid;
  final DateTime? expiresAt;

  const WaitingRoomJoinRequestReceived({
    required this.requestId,
    required this.participantUid,
    this.expiresAt,
  });

  @override
  List<Object?> get props => [requestId, participantUid, expiresAt];
}

/// Periodic tick to drop waiting-room join requests past [WaitingRoomJoinRequest.expiresAt].
class WaitingRoomJoinRequestsExpirationTick extends RoomBlocEvent {
  const WaitingRoomJoinRequestsExpirationTick();
}

/// Debounced retry to resolve waiting-room guest display names via getParticipants.
class WaitingRoomJoinRequestDisplayNameRetry extends RoomBlocEvent {
  const WaitingRoomJoinRequestDisplayNameRetry();
}

/// A waiting-room join request was removed (cancelled, rejected, or admitted).
class WaitingRoomJoinRequestRemoved extends RoomBlocEvent {
  final String requestId;
  final String participantUid;

  const WaitingRoomJoinRequestRemoved({
    required this.requestId,
    required this.participantUid,
  });

  @override
  List<Object?> get props => [requestId, participantUid];
}

/// Host admits a single waiting-room join request.
class AdmitWaitingRoomJoinRequest extends RoomBlocEvent {
  final String requestId;

  const AdmitWaitingRoomJoinRequest({required this.requestId});

  @override
  List<Object?> get props => [requestId];
}

/// Clears [RoomState.shouldShowWaitingRoomJoinRequestNotFoundError] after the
/// user sees the toast.
class WaitingRoomJoinRequestNotFoundErrorConsumed extends RoomBlocEvent {
  const WaitingRoomJoinRequestNotFoundErrorConsumed();
}

/// Host rejects a single waiting-room join request.
class RejectWaitingRoomJoinRequest extends RoomBlocEvent {
  final String requestId;
  final String participantUid;

  const RejectWaitingRoomJoinRequest({
    required this.requestId,
    required this.participantUid,
  });

  @override
  List<Object?> get props => [requestId, participantUid];
}

/// Host admits all pending waiting-room join requests.
class AdmitAllWaitingRoomJoinRequests extends RoomBlocEvent {}

class LeaveRoom extends RoomBlocEvent {}

/// Toggles the local participant's screen share.
///
/// [notificationTitle] / [notificationText] are forwarded to the Android
/// foreground-service notification used during the screen-share session.
///
/// [screenShareSourceId] is the desktop window/screen id from
/// [ScreenSelectDialog]; ignored when stopping share.
class ToggleScreenShare extends RoomBlocEvent {
  final String? notificationTitle;
  final String? notificationText;
  final String? screenShareSourceId;

  const ToggleScreenShare({
    this.notificationTitle,
    this.notificationText,
    this.screenShareSourceId,
  });

  @override
  List<Object?> get props => [
    notificationTitle,
    notificationText,
    screenShareSourceId,
  ];
}

/// Clears [RoomState.shouldShowNotificationPermissionSettings] after the user
/// dismisses the notification permission inform sheet.
class NotificationPermissionSettingsConsumed extends RoomBlocEvent {
  const NotificationPermissionSettingsConsumed();
}

/// Clears ephemeral [RoomState.chatEffects] / [RoomState.chatSystemNotices]
/// after [RoomPage] mirrors them into [ChatController].
class ChatBlocOutputsConsumed extends RoomBlocEvent {
  const ChatBlocOutputsConsumed();
}

class UpdateVideoFPS extends RoomBlocEvent {
  final int fps;

  const UpdateVideoFPS(this.fps);

  @override
  List<Object?> get props => [fps];
}

class UpdateVideoQuality extends RoomBlocEvent {
  final VideoQuality quality;

  const UpdateVideoQuality(this.quality);

  @override
  List<Object?> get props => [quality];
}

class RoomParticipantUpdated extends RoomBlocEvent {
  final List<ParticipantTrack> tracks;

  const RoomParticipantUpdated(this.tracks);

  @override
  List<Object?> get props => [tracks];
}

class RoomMessageReceived extends RoomBlocEvent {
  final String message;
  final String identity;
  final String name;

  const RoomMessageReceived({
    required this.message,
    required this.identity,
    required this.name,
  });

  @override
  List<Object?> get props => [message, identity, name];
}

class ToggleSpeaker extends RoomBlocEvent {}

class StayInMeeting extends RoomBlocEvent {}

class CheckAloneStatus extends RoomBlocEvent {}

class StartPictureInPicture extends RoomBlocEvent {
  final String? videoTrackSid;
  final String? participantIdentity;

  const StartPictureInPicture({this.videoTrackSid, this.participantIdentity});

  @override
  List<Object?> get props => [videoTrackSid, participantIdentity];
}

class StopPictureInPicture extends RoomBlocEvent {}

class InitializePip extends RoomBlocEvent {
  final String roomName;

  const InitializePip({required this.roomName});

  @override
  List<Object?> get props => [roomName];
}

class EnterPipMode extends RoomBlocEvent {
  /// When true (iOS PiP button), start PiP then send the app to the background.
  final bool backgroundApp;

  const EnterPipMode({this.backgroundApp = false});

  @override
  List<Object?> get props => [backgroundApp];
}

/// iOS: refresh native PiP video when active speaker / screen share changes.
class SyncIosPipTrack extends RoomBlocEvent {}

class ExitPipMode extends RoomBlocEvent {}

class PipStateChanged extends RoomBlocEvent {
  final bool isPipActive;

  const PipStateChanged({required this.isPipActive});

  @override
  List<Object?> get props => [isPipActive];
}

class StartConnectionHealthCheck extends RoomBlocEvent {}

class StopConnectionHealthCheck extends RoomBlocEvent {}

class CheckConnectionStatus extends RoomBlocEvent {}

class MlsGroupUpdated extends RoomBlocEvent {}

class SwapCamera extends RoomBlocEvent {}

class ToggleSpeakerPhone extends RoomBlocEvent {}

class SetSpeakerPhone extends RoomBlocEvent {
  final bool enabled;

  const SetSpeakerPhone({required this.enabled});

  @override
  List<Object?> get props => [enabled];
}

/// Hardware or audio-session route change (headphones, Bluetooth, etc.).
class AudioOutputDevicesChanged extends RoomBlocEvent {
  final int? audioDeviceCount;
  final bool hasExternalAudioOutput;
  final bool hasBluetoothAudioOutput;

  const AudioOutputDevicesChanged({
    required this.hasExternalAudioOutput,
    required this.hasBluetoothAudioOutput,
    this.audioDeviceCount,
  });

  @override
  List<Object?> get props => [
    audioDeviceCount,
    hasExternalAudioOutput,
    hasBluetoothAudioOutput,
  ];
}

/// Retry loading participants and resort when loadFrbParticipants fails
class RetryLoadParticipants extends RoomBlocEvent {
  const RetryLoadParticipants();
}

/// Loads decrypted display names from meet-api asynchronously and re-sorts
/// participant tiles when names arrive.
class RefreshParticipantDisplayNames extends RoomBlocEvent {
  const RefreshParticipantDisplayNames();
}

/// Async meet-api participant load after room init (non-blocking).
///
/// On failure, forwards to [RetryLoadParticipants].
class BackgroundRefreshFrbParticipants extends RoomBlocEvent {
  const BackgroundRefreshFrbParticipants();
}

class SetHideSelfView extends RoomBlocEvent {
  final bool hideSelfView;

  const SetHideSelfView({required this.hideSelfView});

  @override
  List<Object?> get props => [hideSelfView];
}

class SetUnsubscribeVideoByDefault extends RoomBlocEvent {
  final bool value;

  const SetUnsubscribeVideoByDefault({required this.value});

  @override
  List<Object?> get props => [value];
}

class MeetingInfoWaitingRoomUpdated extends RoomBlocEvent {
  final bool enabled;

  const MeetingInfoWaitingRoomUpdated({required this.enabled});

  @override
  List<Object?> get props => [enabled];
}

class SetCameraBackgroundBlurEnabled extends RoomBlocEvent {
  final bool enabled;

  const SetCameraBackgroundBlurEnabled({required this.enabled});

  @override
  List<Object?> get props => [enabled];
}

class SetAudioDenoiseEnabled extends RoomBlocEvent {
  final bool enabled;

  const SetAudioDenoiseEnabled({required this.enabled});

  @override
  List<Object?> get props => [enabled];
}

class SetAudioDenoiseType extends RoomBlocEvent {
  final DenoiseType type;

  const SetAudioDenoiseType({required this.type});

  @override
  List<Object?> get props => [type];
}

class SetForceShowConnectionStatusBanner extends RoomBlocEvent {
  final bool value;

  const SetForceShowConnectionStatusBanner({required this.value});

  @override
  List<Object?> get props => [value];
}

/// Event to update audio input device in state
class SetAudioInputDevice extends RoomBlocEvent {
  final MediaDevice device;

  const SetAudioInputDevice({required this.device});

  @override
  List<Object?> get props => [device];
}

/// Event to update video input device in state
class SetVideoInputDevice extends RoomBlocEvent {
  final MediaDevice device;

  const SetVideoInputDevice({required this.device});

  @override
  List<Object?> get props => [device];
}

/// Event to update audio output device in state
class SetAudioOutputDevice extends RoomBlocEvent {
  final MediaDevice device;

  const SetAudioOutputDevice({required this.device});

  @override
  List<Object?> get props => [device];
}

/// Start rejoin meeting process after connection loss
class StartRejoinMeeting extends RoomBlocEvent {
  const StartRejoinMeeting({this.reason});
  final RejoinReason? reason;

  @override
  List<Object?> get props => [reason];
}

/// Update rejoin progress status
class RejoinMeetingProgress extends RoomBlocEvent {
  final RejoinStatus status;

  const RejoinMeetingProgress({required this.status});

  @override
  List<Object?> get props => [status];
}

/// Rejoin meeting completed successfully
class RejoinMeetingCompleted extends RoomBlocEvent {
  const RejoinMeetingCompleted();
}

/// Rejoin meeting failed
class RejoinMeetingFailed extends RoomBlocEvent {
  final String error;

  const RejoinMeetingFailed({required this.error});

  @override
  List<Object?> get props => [error];
}

/// Cancel rejoin meeting process (user requested to leave)
class CancelRejoinMeeting extends RoomBlocEvent {
  const CancelRejoinMeeting();
}

/// Update MLS sync state
class MlsSyncStateUpdated extends RoomBlocEvent {
  final MlsSyncState state;
  final RejoinReason? reason;

  const MlsSyncStateUpdated({required this.state, this.reason});

  @override
  List<Object?> get props => [state];
}

/// Set rejoin failed dialog showing state
class SetRejoinFailedDialogShowing extends RoomBlocEvent {
  final bool isShowing;

  const SetRejoinFailedDialogShowing({required this.isShowing});

  @override
  List<Object?> get props => [isShowing];
}

/// Trigger WebSocket reconnection
class TriggerWebsocketReconnect extends RoomBlocEvent {
  const TriggerWebsocketReconnect();
}

/// Set LiveKit room reconnecting state
class SetLiveKitReconnecting extends RoomBlocEvent {
  final bool isLiveKitReconnecting;

  const SetLiveKitReconnecting({required this.isLiveKitReconnecting});

  @override
  List<Object?> get props => [isLiveKitReconnecting];
}

class SetParticipantRaisedHand extends RoomBlocEvent {
  final String identity;
  final bool raised;

  const SetParticipantRaisedHand({
    required this.identity,
    required this.raised,
  });

  @override
  List<Object?> get props => [identity, raised];
}

/// A remote participant just announced they started recording (validated &
/// MLS-decrypted by the receiver before being dispatched).
class ParticipantRecordingStarted extends RoomBlocEvent {
  final String identity;

  const ParticipantRecordingStarted({required this.identity});

  @override
  List<Object?> get props => [identity];
}

/// A remote participant announced they stopped recording, OR they
/// disconnected from the room while recording.
class ParticipantRecordingStopped extends RoomBlocEvent {
  final String identity;

  const ParticipantRecordingStopped({required this.identity});

  @override
  List<Object?> get props => [identity];
}

/// Start the local recording duration timer (1 Hz).
class StartLocalRecordingTimer extends RoomBlocEvent {
  const StartLocalRecordingTimer();
}

/// Stop and reset the local recording duration timer.
class StopLocalRecordingTimer extends RoomBlocEvent {
  const StopLocalRecordingTimer();
}

/// Tick the local recording duration counter.
class LocalRecordingTimerTick extends RoomBlocEvent {
  const LocalRecordingTimerTick();
}
