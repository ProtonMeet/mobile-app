import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/views/scenes/room/room_bloc.dart';
import 'package:meet/views/scenes/room/room_state.dart';
import 'package:meet/views/scenes/room/widgets/room_reconnecting_progress_indicator.dart';

/// Hides [child] and shows [RoomReconnectingProgressIndicator] while the room
/// is rejoining or LiveKit transport is reconnecting.
class RoomReconnectingGate extends StatelessWidget {
  const RoomReconnectingGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<RoomBloc, RoomState, (bool, bool)>(
      selector: (state) => (state.isRejoining, state.isLiveKitReconnecting),
      builder: (context, data) {
        final isReconnecting = data.$1 || data.$2;
        if (isReconnecting) {
          return const RoomReconnectingProgressIndicator();
        }
        return child;
      },
    );
  }
}
