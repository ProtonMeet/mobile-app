import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

class RoomTopBar extends StatelessWidget {
  final Room room;
  final bool isFullScreen;
  final VoidCallback onFullScreenToggle;
  final VoidCallback onLeave;
  final VoidCallback onSettings;

  const RoomTopBar({
    required this.room,
    required this.isFullScreen,
    required this.onFullScreenToggle,
    required this.onLeave,
    required this.onSettings,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: context.colors.backgroundNorm),
      child: Row(
        children: [
          // Room name and participant count
          Expanded(
            child: Row(
              children: [
                Text(
                  room.name ?? context.local.unnamed_room,
                  style: ProtonStyles.headline(color: context.colors.textNorm),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.backgroundSecondary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${room.remoteParticipants.length + 1} participants',
                    style: ProtonStyles.body2Medium(
                      color: context.colors.textNorm,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Controls
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.settings, color: context.colors.textNorm),
                onPressed: onSettings,
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  color: context.colors.textNorm,
                ),
                onPressed: onFullScreenToggle,
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                icon: const Icon(Icons.exit_to_app),
                label: const Text('Leave'),
                onPressed: onLeave,
                style: TextButton.styleFrom(
                  foregroundColor: context.colors.notificationError,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
