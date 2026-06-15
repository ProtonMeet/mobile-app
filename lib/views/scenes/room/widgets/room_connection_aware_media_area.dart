import 'package:flutter/material.dart';
import 'package:meet/views/scenes/room/widgets/connection_status_banner.dart';
import 'package:meet/views/scenes/room/widgets/room_reconnecting_gate.dart';

/// Standard meeting media chrome: connection status banner above [child],
/// with reconnect loading applied to the media area.
///
/// Side panels (chat, participant list, etc.) remain siblings below this widget.
class RoomConnectionAwareMediaArea extends StatelessWidget {
  const RoomConnectionAwareMediaArea({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const ConnectionStatusBanner(),
        Expanded(
          child: RoomReconnectingGate(child: child),
        ),
      ],
    );
  }
}
