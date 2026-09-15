import 'package:flutter_test/flutter_test.dart';
import 'package:meet/views/scenes/room/chat/chat_controller.dart';
import 'package:meet/views/scenes/room/chat/chat_models.dart';

RoomChatMessage _msg({
  required String id,
  required String identity,
  String message = 'hello',
  int timestamp = 1,
  String? topicId,
  String? inReplyToId,
  bool isMissingRoot = false,
  bool isSystem = false,
}) {
  return RoomChatMessage(
    id: id,
    message: message,
    timestamp: timestamp,
    identity: identity,
    name: identity,
    topicId: topicId,
    inReplyToId: inReplyToId,
    isMissingRoot: isMissingRoot,
    isSystem: isSystem,
  );
}

void main() {
  const localId = 'local-user';
  const otherId = 'other-user';

  group('ChatController', () {
    test('groups messages into threads with replies', () {
      final controller = ChatController(localIdentity: localId);
      controller.receiveMessage(_msg(id: 'root-1', identity: otherId));
      controller.receiveMessage(
        _msg(
          id: 'reply-1',
          identity: otherId,
          topicId: 'root-1',
          inReplyToId: 'root-1',
          timestamp: 2,
        ),
      );

      expect(controller.threads, hasLength(1));
      expect(controller.threads.single.root.id, 'root-1');
      expect(controller.threads.single.replies.single.id, 'reply-1');
    });

    test('creates missing root placeholder for early reply', () {
      final controller = ChatController(localIdentity: localId);
      controller.receiveMessage(
        _msg(
          id: 'reply-1',
          identity: otherId,
          topicId: 'root-1',
          inReplyToId: 'root-1',
        ),
      );

      expect(controller.messages, hasLength(2));
      expect(controller.threads.single.isRootMissing, isTrue);
    });

    test('tracks unread messages and clears them when chat opens', () {
      final controller = ChatController(localIdentity: localId);
      controller.receiveMessage(_msg(id: 'root-1', identity: otherId));

      expect(controller.unreadCount, 1);

      controller.setChatOpen(open: true);

      expect(controller.unreadCount, 0);
      expect(controller.messages.single.seen, isTrue);
    });

    test('adds and removes reactions for a message', () {
      final controller = ChatController(localIdentity: localId);
      controller.receiveMessage(_msg(id: 'msg-1', identity: otherId));

      controller.addReaction(
        reactionId: 'reaction-1',
        messageId: 'msg-1',
        emoji: '👍',
        identity: localId,
      );

      expect(controller.hasLocalReaction('msg-1', '👍'), isTrue);
      expect(controller.findLocalReactionId('msg-1', '👍'), 'reaction-1');

      controller.removeReaction(replacesId: 'reaction-1', identity: localId);

      expect(controller.hasLocalReaction('msg-1', '👍'), isFalse);
    });

    test('ignores duplicate message ids', () {
      final controller = ChatController(localIdentity: localId);
      final first = controller.receiveMessage(
        _msg(id: 'msg-1', identity: otherId),
      );
      final second = controller.receiveMessage(
        _msg(id: 'msg-1', identity: otherId, message: 'duplicate'),
      );

      expect(first, isTrue);
      expect(second, isFalse);
      expect(controller.messages, hasLength(1));
      expect(controller.messages.single.message, 'hello');
    });
  });

  group('isRelevantThreadMessage', () {
    test('notifies on root messages from others', () {
      final message = _msg(id: 'root-1', identity: otherId);
      expect(isRelevantThreadMessage(message, const [], localId), isTrue);
    });

    test('does not notify on own messages', () {
      final message = _msg(id: 'root-1', identity: localId);
      expect(isRelevantThreadMessage(message, const [], localId), isFalse);
    });

    test('does not notify on system or missing-root placeholders', () {
      expect(
        isRelevantThreadMessage(
          _msg(id: 'sys-1', identity: otherId, isSystem: true),
          const [],
          localId,
        ),
        isFalse,
      );
      expect(
        isRelevantThreadMessage(
          _msg(
            id: 'missing-1',
            identity: '',
            topicId: 'missing-1',
            isMissingRoot: true,
          ),
          const [],
          localId,
        ),
        isFalse,
      );
    });

    test('notifies thread reply when local user is root author', () {
      const topicId = 'root-1';
      final chatMessages = [
        _msg(id: topicId, identity: localId, topicId: topicId),
      ];
      final reply = _msg(
        id: 'reply-1',
        identity: otherId,
        topicId: topicId,
        inReplyToId: topicId,
      );

      expect(isRelevantThreadMessage(reply, chatMessages, localId), isTrue);
    });

    test('notifies thread reply when local user has replied in thread', () {
      const topicId = 'root-1';
      final chatMessages = [
        _msg(id: topicId, identity: otherId, topicId: topicId),
        _msg(
          id: 'reply-local',
          identity: localId,
          topicId: topicId,
          inReplyToId: topicId,
        ),
      ];
      final reply = _msg(
        id: 'reply-other',
        identity: otherId,
        topicId: topicId,
        inReplyToId: topicId,
      );

      expect(isRelevantThreadMessage(reply, chatMessages, localId), isTrue);
    });

    test(
      'does not notify thread reply when local user is not a participant',
      () {
        const topicId = 'root-1';
        final chatMessages = [
          _msg(id: topicId, identity: otherId, topicId: topicId),
          _msg(
            id: 'reply-a',
            identity: 'user-a',
            topicId: topicId,
            inReplyToId: topicId,
          ),
        ];
        final reply = _msg(
          id: 'reply-b',
          identity: 'user-b',
          topicId: topicId,
          inReplyToId: topicId,
        );

        expect(isRelevantThreadMessage(reply, chatMessages, localId), isFalse);
      },
    );
  });
}
