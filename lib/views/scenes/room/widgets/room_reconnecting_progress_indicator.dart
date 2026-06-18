import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

/// Centered loading indicator shown over the meeting media area while the
/// room is rejoining or LiveKit is reconnecting.
class RoomReconnectingProgressIndicator extends StatelessWidget {
  const RoomReconnectingProgressIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      width: context.width,
      height: context.height,
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}
