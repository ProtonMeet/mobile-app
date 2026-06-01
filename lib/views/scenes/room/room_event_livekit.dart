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

/// Fired from the bridge whenever LiveKit emits [LocalTrackPublishedEvent].
///
/// Handled in [RoomBloc] to re-arm the E2EE key for the newly-created
/// per-track frame cryptor (see [RoomManager.refreshE2EEKey]). Covers mic,
/// camera, screen-share, fastConnect mic publish, and rejoin re-publishes
/// in one place so individual call sites don't need to remember.
class BridgeLocalTrackPublished extends RoomBlocEvent {
  const BridgeLocalTrackPublished();

  @override
  List<Object?> get props => [];
}
