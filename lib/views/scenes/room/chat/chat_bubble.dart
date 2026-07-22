import 'package:flutter/material.dart';
import 'package:meet/views/scenes/room/chat/chat_controller.dart';
import 'package:meet/views/scenes/room/chat/chat_models.dart';
import 'package:meet/views/scenes/room/chat/chat_widget.dart';
import 'package:meet/views/scenes/room/participant/participant_info.dart';

class ChatBubble extends StatelessWidget {
  final ChatController controller;
  final String userIdentity;
  final String userName;
  final bool chatThreadsEnabled;
  final ChatSendCallback onSend;
  final ChatReactionCallback onToggleReaction;
  final void Function(RoomChatMessage message)? onRetry;
  final void Function(RoomChatMessage message)? onDiscard;
  final List<ParticipantInfo>? participantTracks;

  const ChatBubble({
    required this.controller,
    required this.userIdentity,
    required this.userName,
    required this.onSend,
    required this.onToggleReaction,
    this.chatThreadsEnabled = false,
    this.onRetry,
    this.onDiscard,
    this.participantTracks,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final isLandscape = screenSize.width > screenSize.height;
    final minHeight = isLandscape ? screenSize.height : 300.0;
    return MediaQuery(
      // Remove viewInsets from parent to prevent affecting room layout
      data: mediaQuery.copyWith(viewInsets: EdgeInsets.zero),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(
            minHeight: minHeight.clamp(0.0, screenSize.height),
          ),
          // Restore keyboard insets for chat widget only
          child: MediaQuery(
            data: mediaQuery,
            child: ChatWidget(
              controller: controller,
              localIdentity: userIdentity,
              localName: userName,
              chatThreadsEnabled: chatThreadsEnabled,
              onSend: onSend,
              onToggleReaction: onToggleReaction,
              onRetry: onRetry,
              onDiscard: onDiscard,
              participantTracks: participantTracks,
            ),
          ),
        ),
      ),
    );
  }
}
