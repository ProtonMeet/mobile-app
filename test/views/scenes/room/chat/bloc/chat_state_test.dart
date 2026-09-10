import 'package:flutter_test/flutter_test.dart';
import 'package:meet/views/scenes/room/chat/bloc/chat_state.dart';
import 'package:meet/views/scenes/room/chat/chat_models.dart';

RoomChatMessage _message(String id) {
  return RoomChatMessage(
    id: id,
    message: 'hello',
    timestamp: 1,
    identity: 'user',
    name: 'user',
  );
}

void main() {
  group('ChatState', () {
    test('hasUnread reflects unreadCount', () {
      expect(const ChatState().hasUnread, isFalse);
      expect(const ChatState(unreadCount: 2).hasUnread, isTrue);
    });

    test('equality ignores message list contents', () {
      final left = ChatState(
        revision: 3,
        unreadCount: 1,
        messages: [_message('a')],
      );
      final right = ChatState(
        revision: 3,
        unreadCount: 1,
        messages: [_message('b')],
      );

      expect(left, right);
    });

    test('revision changes break equality', () {
      const first = ChatState(revision: 1);
      const second = ChatState(revision: 2);

      expect(first == second, isFalse);
    });
  });
}
