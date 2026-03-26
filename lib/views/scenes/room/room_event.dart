import 'package:equatable/equatable.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:logger/logger.dart';
import 'package:meet/rust/proton_meet/models/mls_sync_state.dart';
import 'package:meet/rust/proton_meet/models/rejoin_reason.dart';
import 'package:meet/rust/proton_meet/models/upcoming_meeting.dart';
import 'package:meet/views/scenes/prejoin/prejoin_arguments.dart';
import 'package:meet/views/scenes/room/participant_track.dart';
import 'package:meet/views/scenes/room/room_state.dart';

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
  final bool isSpeakerPhoneEnabled;

  const RoomInitialized({
    required this.room,
    required this.listener,
    required this.roomKey,
    required this.meetLinkName,
    required this.displayName,
    required this.preJoinType,
    required this.meetingLink,
    this.isSpeakerPhoneEnabled = false,
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
    isSpeakerPhoneEnabled,
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

  const AddSystemMessage(
    this.message,
    this.identity,
    this.name, {
    this.logLevel = Level.debug,
    this.type = 'system',
  });

  @override
  List<Object?> get props => [message, identity, name];
}

/// room events
class RoomDisposed extends RoomBlocEvent {}

class ToggleFullScreen extends RoomBlocEvent {}

class StartAutoFullScreenTimer extends RoomBlocEvent {}

class ResetAutoFullScreenTimer extends RoomBlocEvent {}

class ToggleChatBubble extends RoomBlocEvent {}

class ToggleParticipantList extends RoomBlocEvent {}

class LeaveRoom extends RoomBlocEvent {}

class ToggleScreenShare extends RoomBlocEvent {}

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

class EnterPipMode extends RoomBlocEvent {}

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

/// Retry loading participants and resort when loadFrbParticipants fails
class RetryLoadParticipants extends RoomBlocEvent {
  const RetryLoadParticipants();
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
