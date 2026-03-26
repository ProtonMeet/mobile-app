// Events
abstract class SimulationEvent {}

class SimulationStarted extends SimulationEvent {}

class SimulationStopped extends SimulationEvent {}

class SimulationRoomAdded extends SimulationEvent {
  final String roomId;
  final List<String> participantNames;

  SimulationRoomAdded({required this.roomId, required this.participantNames});
}

class SimulationRoomRemoved extends SimulationEvent {
  final String roomId;

  SimulationRoomRemoved({required this.roomId});
}

class AddParticipantAndConnect extends SimulationEvent {
  final String displayName;
  final bool enableVideo;
  final bool enableAudio;
  final bool enableE2EE;
  final String roomId;
  final int participantCount;

  AddParticipantAndConnect({
    required this.displayName,
    required this.roomId,
    this.enableVideo = true,
    this.enableAudio = true,
    this.enableE2EE = true,
    this.participantCount = 1,
  });
}

class RemoveParticipant extends SimulationEvent {
  final String roomId;
  final String participantName;

  RemoveParticipant({required this.roomId, required this.participantName});
}

class ToggleParticipantVideo extends SimulationEvent {
  final String roomId;
  final String participantName;
  final bool enableVideo;

  ToggleParticipantVideo({
    required this.roomId,
    required this.participantName,
    required this.enableVideo,
  });
}

class CloseAllRooms extends SimulationEvent {}

// Add new events for UI state changes
class RoomIdChanged extends SimulationEvent {
  final String roomId;

  RoomIdChanged(this.roomId);
}

class ParticipantCountChanged extends SimulationEvent {
  final int count;

  ParticipantCountChanged(this.count);
}

class VideoEnabledChanged extends SimulationEvent {
  final bool enabled;

  // ignore: avoid_positional_boolean_parameters
  VideoEnabledChanged(this.enabled);
}
