import 'package:livekit_client/livekit_client.dart';
import 'package:meet/views/scenes/prejoin/prejoin_arguments.dart';

abstract class WaitingRoomEvent {}

class WaitingRoomInitialized extends WaitingRoomEvent {
  final JoinArgs args;
  final PreJoinType preJoinType;
  final bool isVideoEnabled;
  final bool isAudioEnabled;
  final bool enableE2EE;
  final MediaDevice? selectedVideoDevice;
  final MediaDevice? selectedAudioDevice;
  final MediaDevice? selectedSpeakerDevice;
  final CameraPosition? selectedVideoPosition;
  final VideoParameters selectedVideoParameters;
  final bool isSpeakerPhoneEnabled;

  WaitingRoomInitialized({
    required this.args,
    required this.preJoinType,
    required this.isVideoEnabled,
    required this.isAudioEnabled,
    required this.enableE2EE,
    this.selectedVideoDevice,
    this.selectedAudioDevice,
    this.selectedSpeakerDevice,
    this.selectedVideoPosition,
    this.selectedVideoParameters = VideoParametersPresets.h720_169,
    this.isSpeakerPhoneEnabled = false,
  });
}

class WaitingRoomSetupRoomKey extends WaitingRoomEvent {}

class WaitingRoomNavigateToRoom extends WaitingRoomEvent {}

class WaitingRoomSortParticipants extends WaitingRoomEvent {}

class WaitingRoomDisconnectOnError extends WaitingRoomEvent {}
