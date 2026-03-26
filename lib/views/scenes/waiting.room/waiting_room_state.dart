import 'package:livekit_client/livekit_client.dart';
import 'package:meet/rust/proton_meet/models/meet_info.dart';
import 'package:meet/rust/proton_meet/models/upcoming_meeting.dart';
import 'package:meet/views/scenes/prejoin/prejoin_arguments.dart';
import 'package:meet/views/scenes/room/participant_track.dart';

class WaitingRoomState {
  final JoinArgs args;
  final bool isLoading;
  final PreJoinType preJoinType;
  final String? error;
  final String currentStatus;
  final String statusDescription;
  final List<ParticipantTrack> participantTracks;
  final Room? room;
  final EventsListener<RoomEvent>? listener;
  final String? roomKey;
  final bool decryptingRoomKey;
  final LocalAudioTrack? audioTrack;
  final LocalVideoTrack? videoTrack;
  final CameraPosition? selectedVideoPosition;
  final bool shouldNavigateToRoom;
  final FrbMeetInfo? meetInfo;
  final FrbUpcomingMeeting? meetLink;
  final BaseKeyProvider? keyProvider;

  WaitingRoomState({
    required this.args,
    required this.preJoinType,
    this.keyProvider,
    this.isLoading = false,
    this.error,
    this.currentStatus = "Initializing...",
    this.statusDescription = "",
    this.participantTracks = const [],
    this.room,
    this.listener,
    this.roomKey,
    this.decryptingRoomKey = false,
    this.audioTrack,
    this.videoTrack,
    this.selectedVideoPosition,
    this.shouldNavigateToRoom = false,
    this.meetInfo,
    this.meetLink,
  });

  WaitingRoomState copyWith({
    JoinArgs? args,
    PreJoinType? preJoinType,
    bool? isLoading,
    String? error,
    String? currentStatus,
    String? statusDescription,
    List<ParticipantTrack>? participantTracks,
    Room? room,
    EventsListener<RoomEvent>? listener,
    String? roomKey,
    bool? decryptingRoomKey,
    LocalAudioTrack? audioTrack,
    LocalVideoTrack? videoTrack,
    CameraPosition? selectedVideoPosition,
    bool? shouldNavigateToRoom,
    FrbMeetInfo? meetInfo,
    FrbUpcomingMeeting? meetLink,
    BaseKeyProvider? keyProvider,
  }) {
    return WaitingRoomState(
      args: args ?? this.args,
      preJoinType: preJoinType ?? this.preJoinType,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      currentStatus: currentStatus ?? this.currentStatus,
      statusDescription: statusDescription ?? this.statusDescription,
      participantTracks: participantTracks ?? this.participantTracks,
      room: room ?? this.room,
      listener: listener ?? this.listener,
      roomKey: roomKey ?? this.roomKey,
      decryptingRoomKey: decryptingRoomKey ?? this.decryptingRoomKey,
      audioTrack: audioTrack ?? this.audioTrack,
      videoTrack: videoTrack ?? this.videoTrack,
      selectedVideoPosition:
          selectedVideoPosition ?? this.selectedVideoPosition,
      shouldNavigateToRoom: shouldNavigateToRoom ?? this.shouldNavigateToRoom,
      meetInfo: meetInfo ?? this.meetInfo,
      meetLink: meetLink ?? this.meetLink,
      keyProvider: keyProvider ?? this.keyProvider,
    );
  }
}
