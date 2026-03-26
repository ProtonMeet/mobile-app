import 'package:flutter/material.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:meet/views/scenes/room/chat/chat_widget.dart';
import 'package:meet/views/scenes/room/participant/participant_info.dart';

class ChatBubble extends StatefulWidget {
  final String userIdentity;
  final String userName;
  final List<types.Message> messages;
  final void Function(types.PartialText) onSendPressed;
  final List<ParticipantInfo>? participantTracks;

  const ChatBubble({
    required this.userIdentity,
    required this.userName,
    required this.onSendPressed,
    required this.messages,
    this.participantTracks,
    super.key,
  });

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> {
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
              messages: widget.messages,
              onSendPressed: widget.onSendPressed,
              participantTracks: widget.participantTracks,
            ),
          ),
        ),
      ),
    );
  }
}
