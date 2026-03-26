import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/managers/services/simulation.service.dart';
import 'package:meet/views/scenes/simulation/simulation.event.dart';
import 'package:meet/views/scenes/simulation/simulation.state.dart';

// Bloc
class SimulationBloc extends Bloc<SimulationEvent, SimulationState> {
  final SimulationService _simulationService;

  SimulationBloc({required SimulationService simulationService})
    : _simulationService = simulationService,
      super(SimulationState(rooms: const {})) {
    on<SimulationRoomAdded>(_onRoomAdded);
    on<SimulationRoomRemoved>(_onRoomRemoved);
    on<AddParticipantAndConnect>(_onAddParticipantAndConnect);
    on<CloseAllRooms>(_onCloseAllRooms);
    on<RemoveParticipant>(_onRemoveParticipant);
    on<ToggleParticipantVideo>(_onToggleParticipantVideo);
    on<RoomIdChanged>(_onRoomIdChanged);
    on<ParticipantCountChanged>(_onParticipantCountChanged);
    on<VideoEnabledChanged>(_onVideoEnabledChanged);
  }

  void _onRoomAdded(SimulationRoomAdded event, Emitter<SimulationState> emit) {
    final updatedRooms = Map<String, List<String>>.from(state.rooms);
    final existingParticipants = updatedRooms[event.roomId] ?? [];
    updatedRooms[event.roomId] = [
      ...existingParticipants,
      ...event.participantNames,
    ];
    emit(state.copyWith(rooms: updatedRooms));
  }

  void _onRoomRemoved(
    SimulationRoomRemoved event,
    Emitter<SimulationState> emit,
  ) {
    final updatedRooms = Map<String, List<String>>.from(state.rooms);
    updatedRooms.remove(event.roomId);
    emit(state.copyWith(rooms: updatedRooms));
  }

  Future<void> _onAddParticipantAndConnect(
    AddParticipantAndConnect event,
    Emitter<SimulationState> emit,
  ) async {
    emit(state.copyWith(isConnecting: true));

    try {
      final existingParticipants = state.rooms[event.roomId]?.length ?? 0;
      final remainingSlots = 20 - existingParticipants;
      final actualCount = event.participantCount > remainingSlots
          ? remainingSlots
          : event.participantCount;

      if (actualCount <= 0) {
        // Room is full, can't add more participants
        return;
      }

      for (var i = 0; i < actualCount; i++) {
        final displayName = actualCount > 1
            ? '${event.displayName} ${existingParticipants + i + 1}'
            : event.displayName;

        await _simulationService.addRoom(
          roomID: event.roomId,
          displayName: displayName,
          enableVideo: event.enableVideo,
          enableAudio: event.enableAudio,
          enableE2EE: event.enableE2EE,
        );

        add(
          SimulationRoomAdded(
            roomId: event.roomId,
            participantNames: [displayName],
          ),
        );

        // Add sleep between participants
        await Future.delayed(const Duration(seconds: 2));
      }
    } finally {
      emit(state.copyWith(isConnecting: false));
    }
  }

  Future<void> _onRemoveParticipant(
    RemoveParticipant event,
    Emitter<SimulationState> emit,
  ) async {
    // First remove the participant from the service
    await _simulationService.removeParticipant(
      roomID: event.roomId,
      participantName: event.participantName,
    );

    // Then update the state
    final updatedRooms = Map<String, List<String>>.from(state.rooms);
    final participants = updatedRooms[event.roomId] ?? [];
    participants.remove(event.participantName);

    if (participants.isEmpty) {
      updatedRooms.remove(event.roomId);
    } else {
      updatedRooms[event.roomId] = participants;
    }

    emit(state.copyWith(rooms: updatedRooms));
  }

  void _onToggleParticipantVideo(
    ToggleParticipantVideo event,
    Emitter<SimulationState> emit,
  ) {
    // This is a placeholder for video toggle functionality
    // You'll need to implement the actual video toggle in the SimulationService
  }

  Future<void> _onCloseAllRooms(
    CloseAllRooms event,
    Emitter<SimulationState> emit,
  ) async {
    // Close all rooms in the service
    await _simulationService.closeAllRooms();
    // Clear the state
    emit(state.copyWith(rooms: const {}));
  }

  void _onRoomIdChanged(RoomIdChanged event, Emitter<SimulationState> emit) {
    emit(state.copyWith(roomId: event.roomId));
  }

  void _onParticipantCountChanged(
    ParticipantCountChanged event,
    Emitter<SimulationState> emit,
  ) {
    emit(state.copyWith(participantCount: event.count));
  }

  void _onVideoEnabledChanged(
    VideoEnabledChanged event,
    Emitter<SimulationState> emit,
  ) {
    emit(state.copyWith(enableVideo: event.enabled));
  }
}
