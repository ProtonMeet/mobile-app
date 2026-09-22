import 'package:flutter_test/flutter_test.dart';
import 'package:meet/utils/mentions/mention_token.dart';
import 'package:meet/views/scenes/room/chat/bloc/chat_bloc.dart';
import 'package:meet/views/scenes/room/chat/bloc/chat_event.dart';
import 'package:meet/views/scenes/room/chat/bloc/chat_incoming_notification.dart';
import 'package:meet/views/scenes/room/chat/bloc/chat_transport.dart';
import 'package:meet/views/scenes/room/chat/chat_controller.dart';
import 'package:meet/views/scenes/room/chat/chat_models.dart';

/// In-memory [ChatTransport]: records what was composed and published, and
/// lets a test decide what compose/publish do.
class FakeChatTransport implements ChatTransport {
  FakeChatTransport({this.localIdentity = 'me'});

  @override
  String localIdentity;

  /// When false, every publish attempt fails.
  bool publishSucceeds = true;

  /// When set, compose throws instead of returning a payload.
  Object? composeError;

  int publishAttempts = 0;
  int nextEchoId = 1;

  final List<String> composedMessages = [];
  final List<({String targetId, String emoji})> composedReactions = [];
  final List<({String targetId, String replacesId})> composedUnreacts = [];

  @override
  Future<ComposedChatEvent> composeMessage({
    required String text,
    String? replyToId,
    String? topicId,
  }) async {
    if (composeError != null) {
      throw composeError!;
    }
    composedMessages.add(text);
    return ComposedChatEvent(
      payload: const [1, 2, 3],
      id: 'echo-${nextEchoId++}',
      senderParticipantId: localIdentity,
      receivedAtMs: 1000,
      text: text,
      inReplyToId: replyToId,
      topicId: topicId,
    );
  }

  @override
  Future<ComposedChatEvent> composeReaction({
    required String targetId,
    required String emoji,
  }) async {
    if (composeError != null) {
      throw composeError!;
    }
    composedReactions.add((targetId: targetId, emoji: emoji));
    return ComposedChatEvent(
      payload: const [4, 5],
      id: 'reaction-${nextEchoId++}',
      senderParticipantId: localIdentity,
      receivedAtMs: 1000,
    );
  }

  @override
  Future<ComposedChatEvent> composeUnreact({
    required String targetId,
    required String replacesId,
  }) async {
    if (composeError != null) {
      throw composeError!;
    }
    composedUnreacts.add((targetId: targetId, replacesId: replacesId));
    return ComposedChatEvent(
      payload: const [6, 7],
      id: 'unreact-${nextEchoId++}',
      senderParticipantId: localIdentity,
      receivedAtMs: 1000,
    );
  }

  @override
  Future<bool> publish(List<int> payload) async {
    publishAttempts++;
    return publishSucceeds;
  }
}

void main() {
  late FakeChatTransport transport;
  late ChatBloc bloc;
  late List<ChatIncomingNotification> toasts;
  var threadedChatEnabled = true;
  var chatMentionsEnabled = false;
  var participants = 3;

  ChatBloc buildBloc() {
    final created = ChatBloc(
      transport: transport,
      isThreadedChatEnabled: () => threadedChatEnabled,
      isChatMentionsEnabled: () => chatMentionsEnabled,
      participantCount: () => participants,
      // No real waiting; the retry schedule itself is what we assert on.
      publishRetryDelays: const [Duration.zero, Duration.zero],
    );
    toasts = [];
    created.incomingMessageToasts.listen(toasts.add);
    addTearDown(created.close);
    return created;
  }

  setUp(() {
    threadedChatEnabled = true;
    chatMentionsEnabled = false;
    participants = 3;
    transport = FakeChatTransport();
    bloc = buildBloc();
  });

  /// Adds an incoming message from someone else and settles the bloc.
  Future<void> receive(
    String id, {
    String identity = 'alice',
    String? topicId,
    bool notify = true,
    int? timestamp,
  }) async {
    bloc.add(
      ChatMessageReceived(
        id: id,
        message: 'hello $id',
        timestamp: timestamp ?? DateTime.now().millisecondsSinceEpoch,
        identity: identity,
        name: identity,
        topicId: topicId,
        notify: notify,
      ),
    );
    await pumpEventQueue();
  }

  group('sending', () {
    test('publishes the message and marks it sent', () async {
      bloc.add(const ChatMessageSubmitted(text: 'hi', senderDisplayName: 'Me'));
      await pumpEventQueue();

      expect(transport.composedMessages, ['hi']);
      expect(transport.publishAttempts, 1);

      final sent = bloc.state.messages.single;
      expect(sent.id, 'echo-1');
      expect(sent.message, 'hi');
      expect(sent.status, ChatMessageStatus.sent);
      // Our own message is never unread.
      expect(bloc.state.unreadCount, 0);
    });

    test('trims the text before composing', () async {
      bloc.add(
        const ChatMessageSubmitted(text: '  hi  ', senderDisplayName: 'Me'),
      );
      await pumpEventQueue();

      expect(transport.composedMessages, ['hi']);
    });

    test('shows the echo as pending before the publish resolves', () async {
      final states = <ChatMessageStatus?>[];
      final sub = bloc.stream.listen(
        (state) => states.add(state.messages.singleOrNull?.status),
      );

      bloc.add(const ChatMessageSubmitted(text: 'hi', senderDisplayName: 'Me'));
      await pumpEventQueue();
      await sub.cancel();

      expect(states, contains(ChatMessageStatus.pending));
      expect(states.last, ChatMessageStatus.sent);
    });

    test('retries publishing and marks failed once attempts run out', () async {
      transport.publishSucceeds = false;

      bloc.add(const ChatMessageSubmitted(text: 'hi', senderDisplayName: 'Me'));
      await pumpEventQueue();

      expect(transport.publishAttempts, 2);
      expect(bloc.state.messages.single.status, ChatMessageStatus.failed);
    });

    test('keeps the text in the transcript when composing throws', () async {
      transport.composeError = Exception('mls not ready');

      bloc.add(const ChatMessageSubmitted(text: 'hi', senderDisplayName: 'Me'));
      await pumpEventQueue();

      final failed = bloc.state.messages.single;
      expect(failed.message, 'hi');
      expect(failed.status, ChatMessageStatus.failed);
      expect(transport.publishAttempts, 0);
    });

    test('does nothing when the text is blank', () async {
      bloc.add(
        const ChatMessageSubmitted(text: '   ', senderDisplayName: 'Me'),
      );
      await pumpEventQueue();

      expect(transport.composedMessages, isEmpty);
      expect(bloc.state.messages, isEmpty);
    });

    test('does nothing when threaded chat is disabled', () async {
      threadedChatEnabled = false;

      bloc.add(const ChatMessageSubmitted(text: 'hi', senderDisplayName: 'Me'));
      await pumpEventQueue();

      expect(transport.composedMessages, isEmpty);
      expect(bloc.state.messages, isEmpty);
    });

    test('retry replaces the failed message with a fresh send', () async {
      transport.publishSucceeds = false;
      bloc.add(const ChatMessageSubmitted(text: 'hi', senderDisplayName: 'Me'));
      await pumpEventQueue();
      expect(bloc.state.messages.single.status, ChatMessageStatus.failed);

      transport.publishSucceeds = true;
      bloc.add(
        const ChatMessageRetryRequested(
          messageId: 'echo-1',
          text: 'hi',
          senderDisplayName: 'Me',
        ),
      );
      await pumpEventQueue();

      expect(transport.composedMessages, ['hi', 'hi']);
      final retried = bloc.state.messages.single;
      expect(retried.id, 'echo-2');
      expect(retried.status, ChatMessageStatus.sent);
    });

    test('discarding removes the message', () async {
      bloc.add(const ChatMessageSubmitted(text: 'hi', senderDisplayName: 'Me'));
      await pumpEventQueue();

      bloc.add(const ChatMessageDiscarded('echo-1'));
      await pumpEventQueue();

      expect(bloc.state.messages, isEmpty);
    });
  });

  group('reactions', () {
    setUp(() async {
      await receive('m1');
    });

    test('adds the reaction locally and publishes it', () async {
      bloc.add(const ChatReactionToggled(messageId: 'm1', emoji: '👍'));
      await pumpEventQueue();

      expect(transport.composedReactions, [(targetId: 'm1', emoji: '👍')]);
      expect(bloc.controller.hasLocalReaction('m1', '👍'), isTrue);
    });

    test('rapid duplicate reaction taps compose at most once', () async {
      bloc.add(const ChatReactionToggled(messageId: 'm1', emoji: '👍'));
      bloc.add(const ChatReactionToggled(messageId: 'm1', emoji: '👍'));
      await pumpEventQueue();

      expect(transport.composedReactions.length, lessThanOrEqualTo(1));
    });

    test('rolls the reaction back when publishing fails', () async {
      transport.publishSucceeds = false;

      bloc.add(const ChatReactionToggled(messageId: 'm1', emoji: '👍'));
      await pumpEventQueue();

      expect(bloc.controller.hasLocalReaction('m1', '👍'), isFalse);
    });

    test('toggling the same emoji again unreacts', () async {
      bloc.add(const ChatReactionToggled(messageId: 'm1', emoji: '👍'));
      await pumpEventQueue();
      final reactionId = bloc.controller.findLocalReactionId('m1', '👍');

      bloc.add(const ChatReactionToggled(messageId: 'm1', emoji: '👍'));
      await pumpEventQueue();

      expect(transport.composedUnreacts, [
        (targetId: 'm1', replacesId: reactionId),
      ]);
      expect(bloc.controller.hasLocalReaction('m1', '👍'), isFalse);
    });

    test('restores the reaction when the unreact fails to publish', () async {
      bloc.add(const ChatReactionToggled(messageId: 'm1', emoji: '👍'));
      await pumpEventQueue();

      transport.publishSucceeds = false;
      bloc.add(const ChatReactionToggled(messageId: 'm1', emoji: '👍'));
      await pumpEventQueue();

      expect(bloc.controller.hasLocalReaction('m1', '👍'), isTrue);
    });

    test('applies a remote reaction', () async {
      bloc.add(
        const ChatReactionReceived(
          reactionId: 'r1',
          senderIdentity: 'alice',
          targetId: 'm1',
          emoji: '❤️',
        ),
      );
      await pumpEventQueue();

      expect(bloc.state.messages.single.reactions['❤️'], ['alice']);
    });

    test('ignores a remote reaction with an implausible emoji', () async {
      bloc.add(
        const ChatReactionReceived(
          reactionId: 'r1',
          senderIdentity: 'alice',
          targetId: 'm1',
          emoji: 'this-is-not-an-emoji',
        ),
      );
      await pumpEventQueue();

      expect(bloc.state.messages.single.hasReactions, isFalse);
    });

    test('ignores a remote reaction with an empty emoji', () async {
      bloc.add(
        const ChatReactionReceived(
          reactionId: 'r1',
          senderIdentity: 'alice',
          targetId: 'm1',
          emoji: '',
        ),
      );
      await pumpEventQueue();

      expect(bloc.state.messages.single.hasReactions, isFalse);
    });

    test('ignores a remote reaction with no target', () async {
      bloc.add(
        const ChatReactionReceived(
          reactionId: 'r1',
          senderIdentity: 'alice',
          emoji: '👍',
        ),
      );
      await pumpEventQueue();

      expect(bloc.state.messages.single.hasReactions, isFalse);
    });

    test('a remote unreact withdraws that sender reaction', () async {
      bloc.add(
        const ChatReactionReceived(
          reactionId: 'r1',
          senderIdentity: 'alice',
          targetId: 'm1',
          emoji: '❤️',
        ),
      );
      await pumpEventQueue();
      expect(bloc.state.messages.single.reactions['❤️'], ['alice']);

      bloc.add(
        const ChatReactionReceived(
          reactionId: 'r2',
          senderIdentity: 'alice',
          replacesId: 'r1',
        ),
      );
      await pumpEventQueue();

      expect(bloc.state.messages.single.hasReactions, isFalse);
    });

    test('ignores an unreact aimed at another participant reaction', () async {
      bloc.add(
        const ChatReactionReceived(
          reactionId: 'r1',
          senderIdentity: 'alice',
          targetId: 'm1',
          emoji: '❤️',
        ),
      );
      await pumpEventQueue();

      // Bob may not withdraw Alice's reaction.
      bloc.add(
        const ChatReactionReceived(
          reactionId: 'r2',
          senderIdentity: 'bob',
          replacesId: 'r1',
        ),
      );
      await pumpEventQueue();

      expect(bloc.state.messages.single.reactions['❤️'], ['alice']);
    });

    test('does nothing when threaded chat is disabled', () async {
      threadedChatEnabled = false;

      bloc.add(const ChatReactionToggled(messageId: 'm1', emoji: '👍'));
      await pumpEventQueue();

      expect(transport.composedReactions, isEmpty);
      expect(bloc.controller.hasLocalReaction('m1', '👍'), isFalse);
    });

    test('leaves the reaction off when composing throws', () async {
      transport.composeError = Exception('mls not ready');

      bloc.add(const ChatReactionToggled(messageId: 'm1', emoji: '👍'));
      await pumpEventQueue();

      expect(bloc.controller.hasLocalReaction('m1', '👍'), isFalse);
      expect(bloc.state.messages.single.hasReactions, isFalse);
      expect(transport.publishAttempts, 0);
    });
  });

  group('receiving', () {
    test(
      'counts an incoming message as unread while the panel is closed',
      () async {
        await receive('m1');

        expect(bloc.state.unreadCount, 1);
        expect(bloc.state.unseenRootCount, 1);
        expect(toasts.map((n) => n.message.id), ['m1']);
      },
    );

    test('marks it seen and raises no toast while the panel is open', () async {
      bloc.add(const ChatPanelVisibilityChanged(isOpen: true));
      await pumpEventQueue();

      await receive('m1');

      expect(bloc.state.unreadCount, 0);
      expect(toasts, isEmpty);
    });

    test('ignores a duplicate message id', () async {
      await receive('m1');
      await receive('m1');

      expect(bloc.state.messages.length, 1);
      expect(bloc.state.unreadCount, 1);
      expect(toasts.length, 1);
    });

    test('never toasts our own message', () async {
      await receive('m1', identity: 'me');

      expect(toasts, isEmpty);
    });

    test('honours the caller opting out of a toast', () async {
      await receive('m1', notify: false);

      expect(bloc.state.unreadCount, 1);
      expect(toasts, isEmpty);
    });

    test('does not toast a reply in a thread we are not part of', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await receive('root', timestamp: now - 2000);
      await receive('reply', topicId: 'root', timestamp: now - 1000);

      expect(toasts.map((n) => n.message.id), ['root']);
    });

    test('toasts a reply in a thread we started', () async {
      bloc.add(
        const ChatMessageSubmitted(text: 'my root', senderDisplayName: 'Me'),
      );
      await pumpEventQueue();

      await receive('reply', topicId: 'echo-1');

      expect(toasts.map((n) => n.message.id), ['reply']);
    });

    test('ignores stale messages older than 8 seconds', () async {
      final stale = DateTime.now().millisecondsSinceEpoch - 9000;
      await receive('stale', timestamp: stale);

      expect(bloc.state.unreadCount, 1);
      expect(toasts, isEmpty);
    });

    test('toasts a direct mention when mentions are enabled', () async {
      chatMentionsEnabled = true;
      const localId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
      transport.localIdentity = localId;
      bloc.controller.updateLocalIdentity(localId);
      final token = getMentionToken(localId);
      bloc.add(
        ChatMessageReceived(
          id: 'mention',
          message: 'ping $token',
          timestamp: DateTime.now().millisecondsSinceEpoch,
          identity: 'alice',
          name: 'Alice',
          notify: true,
        ),
      );
      await pumpEventQueue();

      expect(toasts.single.isMention, isTrue);
      expect(toasts.single.message.id, 'mention');
    });

    test('mention overrides thread relevance filter', () async {
      chatMentionsEnabled = true;
      const localId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
      transport.localIdentity = localId;
      bloc.controller.updateLocalIdentity(localId);
      final token = getMentionToken(localId);
      await receive('root', timestamp: DateTime.now().millisecondsSinceEpoch);
      toasts.clear();

      bloc.add(
        ChatMessageReceived(
          id: 'mention-reply',
          message: 'hey $token',
          timestamp: DateTime.now().millisecondsSinceEpoch,
          identity: 'bob',
          name: 'Bob',
          topicId: 'root',
          notify: true,
        ),
      );
      await pumpEventQueue();

      expect(toasts.single.isMention, isTrue);
      expect(toasts.single.message.id, 'mention-reply');
    });

    test('re-reporting the current panel visibility emits nothing', () async {
      var emissions = 0;
      final sub = bloc.stream.listen((_) => emissions++);

      // The panel is already closed; a redundant report must not invalidate
      // ChatState for every listener in the room.
      bloc.add(const ChatPanelVisibilityChanged(isOpen: false));
      await pumpEventQueue();
      await sub.cancel();

      expect(emissions, 0);
    });

    test('opening the panel marks everything seen', () async {
      await receive('m1');
      await receive('m2');
      expect(bloc.state.unreadCount, 2);

      bloc.add(const ChatPanelVisibilityChanged(isOpen: true));
      await pumpEventQueue();

      expect(bloc.state.unreadCount, 0);
      expect(bloc.state.isPanelOpen, isTrue);
    });
  });

  group('system notices', () {
    test('adds a join notice in a small meeting', () async {
      bloc.add(
        const ChatSystemNoticeAdded(
          message: '',
          identity: 'alice-id',
          name: 'Alice',
          joinLeaveKind: ChatJoinLeaveKind.joined,
          meetingName: 'Standup',
        ),
      );
      await pumpEventQueue();

      final notice = bloc.state.messages.single;
      expect(notice.isSystem, isTrue);
      expect(notice.joinLeaveKind, ChatJoinLeaveKind.joined);
      expect(notice.joinLeaveMeetingName, 'Standup');
      // System notices never contribute to the unread badge.
      expect(bloc.state.unreadCount, 0);
    });

    test('suppresses join/leave notices in a large meeting', () async {
      participants = ChatBloc.joinLeaveSuppressThreshold;

      bloc.add(
        const ChatSystemNoticeAdded(
          message: '',
          identity: 'alice-id',
          name: 'Alice',
          joinLeaveKind: ChatJoinLeaveKind.joined,
        ),
      );
      await pumpEventQueue();

      expect(bloc.state.messages, isEmpty);
    });

    test('keeps non join/leave notices in a large meeting', () async {
      participants = 500;

      bloc.add(
        const ChatSystemNoticeAdded(
          message: 'Room disconnected',
          identity: 'system',
          name: 'System',
        ),
      );
      await pumpEventQueue();

      expect(bloc.state.messages.single.message, 'Room disconnected');
    });
  });

  group('local identity', () {
    test('adopts the identity once the room reports one', () async {
      transport.localIdentity = '';
      bloc.add(const ChatLocalIdentityChanged('participant-uuid'));
      await pumpEventQueue();

      expect(bloc.state.localIdentity, 'participant-uuid');
    });

    test('ignores an empty identity', () async {
      bloc.add(const ChatLocalIdentityChanged('real-id'));
      await pumpEventQueue();
      bloc.add(const ChatLocalIdentityChanged(''));
      await pumpEventQueue();

      expect(bloc.state.localIdentity, 'real-id');
    });

    test('ignores a repeat of the identity it already holds', () async {
      bloc.add(const ChatLocalIdentityChanged('real-id'));
      await pumpEventQueue();
      final revision = bloc.state.revision;

      bloc.add(const ChatLocalIdentityChanged('real-id'));
      await pumpEventQueue();

      expect(bloc.state.revision, revision);
    });

    test('adopts the transport identity when sending', () async {
      transport.localIdentity = 'participant-uuid';

      bloc.add(const ChatMessageSubmitted(text: 'hi', senderDisplayName: 'Me'));
      await pumpEventQueue();

      expect(bloc.state.localIdentity, 'participant-uuid');
    });

    test('attributes a reaction to the adopted identity', () async {
      transport.localIdentity = 'participant-uuid';
      await receive('m1');

      // The controller owns the local id; reacting under a different one would
      // make the later un-react compose a duplicate instead of a withdrawal.
      bloc.add(const ChatReactionToggled(messageId: 'm1', emoji: '👍'));
      await pumpEventQueue();

      expect(bloc.state.messages.single.reactions['👍'], ['participant-uuid']);
      expect(bloc.controller.hasLocalReaction('m1', '👍'), isTrue);
    });
  });

  group('transcript writes from the widget layer', () {
    test('does not dispose injected controller on close', () async {
      final customController = ChatController(localIdentity: 'me');
      final localBloc = ChatBloc(
        transport: transport,
        isThreadedChatEnabled: () => true,
        isChatMentionsEnabled: () => false,
        participantCount: () => 1,
        controller: customController,
        publishRetryDelays: const [Duration.zero],
      );

      await localBloc.close();

      var notified = false;
      customController.addListener(() => notified = true);
      customController.updateLocalIdentity('other-id');
      expect(notified, isTrue);
    });

    test('a direct controller mutation reaches the state', () async {
      await receive('m1');
      expect(bloc.state.unreadCount, 1);

      // ChatWidget still mutates the controller directly, so the bloc listens
      // to it; otherwise those writes would never reach a BlocSelector.
      bloc.controller.markAllSeen();
      await pumpEventQueue();

      expect(bloc.state.unreadCount, 0);
    });

    test('revision advances even when no counter changes', () async {
      await receive('m1');
      bloc.controller.markAllSeen();
      await pumpEventQueue();
      final before = bloc.state;

      // Expanding a thread with nothing unseen in it moves no counter, so
      // revision is the only thing that can force dependents to rebuild.
      bloc.controller.setThreadExpanded('m1', expanded: true);
      await pumpEventQueue();

      expect(bloc.state.unreadCount, before.unreadCount);
      expect(bloc.state.revision, greaterThan(before.revision));
    });
  });

  group('lifecycle', () {
    test('closing ends the toast stream', () async {
      // Built by hand rather than via buildBloc: that registers a tearDown
      // close, and close() disposes the controller, so it is not idempotent.
      final closing = ChatBloc(
        transport: FakeChatTransport(),
        isThreadedChatEnabled: () => true,
        isChatMentionsEnabled: () => false,
        participantCount: () => 1,
      );
      final done = expectLater(closing.incomingMessageToasts, emitsDone);

      await closing.close();

      await done;
    });

    test('a publish still retrying at close does not emit', () async {
      final closingTransport = FakeChatTransport()..publishSucceeds = false;
      final closing = ChatBloc(
        transport: closingTransport,
        isThreadedChatEnabled: () => true,
        isChatMentionsEnabled: () => false,
        participantCount: () => 1,
        publishRetryDelays: const [Duration.zero, Duration(milliseconds: 20)],
      );

      closing.add(
        const ChatMessageSubmitted(text: 'hi', senderDisplayName: 'Me'),
      );
      await pumpEventQueue();
      await closing.close();

      // The retry schedule outlives the call; emitting into a closed bloc or
      // touching the disposed controller would throw here.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(closing.isClosed, isTrue);
    });
  });
}
