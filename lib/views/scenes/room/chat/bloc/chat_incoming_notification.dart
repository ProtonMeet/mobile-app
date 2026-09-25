import 'package:meet/views/scenes/room/chat/chat_models.dart';

/// One-shot chat notification emitted while the panel is closed.
class ChatIncomingNotification {
  const ChatIncomingNotification({
    required this.message,
    required this.isMention,
  });

  final RoomChatMessage message;
  final bool isMention;
}
