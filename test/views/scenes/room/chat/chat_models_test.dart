import 'package:flutter_test/flutter_test.dart';
import 'package:meet/views/scenes/room/chat/chat_models.dart';

RoomChatMessage _message({
  required String id,
  String message = 'hello',
  String identity = 'user-a',
  String? topicId,
  String? inReplyToId,
  bool isMissingRoot = false,
  bool isSystem = false,
  Map<String, List<String>>? reactions,
}) {
  return RoomChatMessage(
    id: id,
    message: message,
    timestamp: 100,
    identity: identity,
    name: identity,
    topicId: topicId,
    inReplyToId: inReplyToId,
    isMissingRoot: isMissingRoot,
    isSystem: isSystem,
    reactions: reactions,
  );
}

void main() {
  group('RoomChatMessage', () {
    test('isRoot when topicId is null or equals id', () {
      expect(_message(id: 'root-1').isRoot, isTrue);
      expect(_message(id: 'root-1', topicId: 'root-1').isRoot, isTrue);
    });

    test('isReply when topicId points to another message', () {
      final reply = _message(
        id: 'reply-1',
        topicId: 'root-1',
        inReplyToId: 'root-1',
      );
      expect(reply.isReply, isTrue);
      expect(reply.isRoot, isFalse);
    });

    test('hasReactions ignores empty emoji lists', () {
      expect(
        _message(id: 'm-1', reactions: {'👍': []}).hasReactions,
        isFalse,
      );
      expect(
        _message(id: 'm-1', reactions: {'👍': ['user-a']}).hasReactions,
        isTrue,
      );
    });

    test('missingRoot factory marks placeholder state', () {
      final root = RoomChatMessage.missingRoot(
        rootId: 'root-1',
        timestamp: 42,
      );

      expect(root.id, 'root-1');
      expect(root.topicId, 'root-1');
      expect(root.isMissingRoot, isTrue);
      expect(root.seen, isTrue);
      expect(root.message, isEmpty);
    });

    test('withEchoPreservingLocalUi keeps local thread state', () {
      final local = _message(
        id: 'm-1',
        message: 'draft',
        reactions: {'👍': ['me']},
      ).copyWith(expanded: true, replyDraft: 'typing', seen: true);

      final echo = _message(
        id: 'm-1',
        message: 'sent',
        identity: 'me',
      );

      final merged = local.withEchoPreservingLocalUi(echo);

      expect(merged.message, 'sent');
      expect(merged.expanded, isTrue);
      expect(merged.replyDraft, 'typing');
      expect(merged.seen, isTrue);
      expect(merged.reactions, {'👍': ['me']});
    });

    test('copyWith can clear reply draft', () {
      final message = _message(id: 'm-1').copyWith(replyDraft: 'draft');
      final cleared = message.copyWith(clearReplyDraft: true);

      expect(cleared.replyDraft, isNull);
    });
  });

  group('cloneReactions', () {
    test('deep copies emoji identity lists', () {
      final source = {'👍': ['a', 'b']};
      final cloned = cloneReactions(source);

      cloned['👍']!.add('c');

      expect(source['👍'], ['a', 'b']);
      expect(cloned['👍'], ['a', 'b', 'c']);
    });
  });

  group('ChatThread', () {
    test('hasReplies reflects reply list', () {
      final withReplies = ChatThread(
        root: _message(id: 'root-1'),
        replies: [_message(id: 'reply-1', topicId: 'root-1')],
        isRootMissing: false,
      );
      final withoutReplies = ChatThread(
        root: _message(id: 'root-2'),
        replies: const [],
        isRootMissing: false,
      );

      expect(withReplies.hasReplies, isTrue);
      expect(withoutReplies.hasReplies, isFalse);
    });
  });
}
