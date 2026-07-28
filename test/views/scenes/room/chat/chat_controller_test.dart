import 'package:flutter_test/flutter_test.dart';
import 'package:meet/views/scenes/room/chat/chat_controller.dart';
import 'package:meet/views/scenes/room/chat/chat_models.dart';

RoomChatMessage _msg({
  required String id,
  required String identity,
  String? topicId,
  String? inReplyToId,
  bool isMissingRoot = false,
  bool isSystem = false,
}) {
  return RoomChatMessage(
    id: id,
    message: 'hello',
    timestamp: 1,
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

      expect(
        isRelevantThreadMessage(reply, chatMessages, localId),
        isTrue,
      );
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

      expect(
        isRelevantThreadMessage(reply, chatMessages, localId),
        isTrue,
      );
    });

    test('does not notify thread reply when local user is not a participant', () {
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

      expect(
        isRelevantThreadMessage(reply, chatMessages, localId),
        isFalse,
      );
    });
  });
}
