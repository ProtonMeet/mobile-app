import 'package:livekit_client/livekit_client.dart';

import 'room_event.dart';

class BridgeParticipantConnected extends RoomBlocEvent {
  final ParticipantConnectedEvent event;

  const BridgeParticipantConnected(this.event);

  @override
  List<Object?> get props => [event];
}

class BridgeParticipantDisconnected extends RoomBlocEvent {
  final ParticipantDisconnectedEvent event;

  const BridgeParticipantDisconnected(this.event);

  @override
  List<Object?> get props => [event];
}

class BridgeDataReceived extends RoomBlocEvent {
  final DataReceivedEvent event;

  const BridgeDataReceived(this.event);

  @override
  List<Object?> get props => [event];
}

class BridgeTokenUpdated extends RoomBlocEvent {
  final String token;

  const BridgeTokenUpdated(this.token);

  @override
  List<Object?> get props => [token];
}
