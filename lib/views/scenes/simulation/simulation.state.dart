import 'package:meet/constants/constants.dart';

// State
class SimulationState {
  final Map<String, List<String>> rooms; // roomId -> list of participant names
  final bool isConnecting;
  final String roomId;
  final int participantCount;
  final bool enableVideo;

  SimulationState({
    required this.rooms,
    this.isConnecting = false,
    this.roomId = defaultRoomId,
    this.participantCount = defaultSimulationParticipantCount,
    this.enableVideo = defaultSimulationEnableVideo,
  });

  SimulationState copyWith({
    Map<String, List<String>>? rooms,
    bool? isConnecting,
    String? roomId,
    int? participantCount,
    bool? enableVideo,
  }) {
    return SimulationState(
      rooms: rooms ?? this.rooms,
      isConnecting: isConnecting ?? this.isConnecting,
      roomId: roomId ?? this.roomId,
      participantCount: participantCount ?? this.participantCount,
      enableVideo: enableVideo ?? this.enableVideo,
    );
  }
}
