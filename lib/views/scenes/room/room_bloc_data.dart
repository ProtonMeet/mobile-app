// room_tracks_handlers.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/manager.factory.dart';

import 'message_topic.dart';
import 'room_event.dart';
import 'room_event_livekit.dart';
import 'room_state.dart';

mixin RoomDataHandlers on Bloc<RoomBlocEvent, RoomState> {
  void registerDataHandlers() {
    /// livekit events
    on<BridgeDataReceived>(_onDataReceived);
    on<BridgeTokenUpdated>(_onTokenUpdated);
  }

  Future<void> _onDataReceived(
    BridgeDataReceived event,
    Emitter<RoomState> emit,
  ) async {
    try {
      final topic = MessageTopic.values.firstWhere(
        (e) => e.name == event.event.topic,
      );
      if (topic == MessageTopic.e2eeMessage) {
        await _handleE2EEMessage(event.event);
      }
    } catch (e) {
      try {
        _handleWebChatMessage(event.event);
      } catch (e) {
        // l.logger.d('Error handling web chat message: $e');
        // if (mounted) {
        //   await context.showDataReceivedDialog(e.toString());
        // }
        // TODO(fix): emit error here and return
      }
    }
  }

  Future<void> _handleE2EEMessage(DataReceivedEvent event) async {}

  /// to-do: this will be deprecated when web chat is encrypting message content
  Future<void> _handleWebChatMessage(DataReceivedEvent event) async {}

  Future<void> _onTokenUpdated(
    BridgeTokenUpdated event,
    Emitter<RoomState> emit,
  ) async {
    final appCoreManager = ManagerFactory().get<AppCoreManager>();
    await appCoreManager.appCore.updateLivekitAccessToken(
      accessToken: event.token,
    );
  }
}
