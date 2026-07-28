import 'package:flutter/foundation.dart';

import 'chat_models.dart';

/// Default quick-reaction emojis surfaced on hover / long-press.
const List<String> kQuickReactionEmojis = ['👍', '❤️', '😂', '😮', '🥲', '👎'];

/// Holds the full chat state for a room (messages, threads, reactions) and
/// implements the reducer-equivalent actions from the Chat Threads spec.
///
/// This is the single source of truth for the chat panel. meet-core owns all
/// encryption; this controller only manipulates decoded structures.
class ChatController extends ChangeNotifier {
  ChatController({required this.localIdentity});

  /// Local participant identity (MLS sender id). May be updated once known.
  String localIdentity;

  /// Chronological (oldest → newest) list of all chat messages.
  final List<RoomChatMessage> _messages = [];

  /// reactionEventId → ChatReactionRef.
  final Map<String, ChatReactionRef> _reactionIndex = {};

  /// Whether the chat panel is currently open (drives seen calculation).
  bool isChatOpen = false;

  /// Main composer draft.
  String draftMessage = '';

  bool _threadIndexDirty = true;
  final List<String> _rootIds = [];
  final Map<String, List<String>> _replyIdsByTopic = {};
  final Set<String> _replyIds = {};

  List<RoomChatMessage> get messages => List.unmodifiable(_messages);

  /// Grouped threads for the main chat list. Resolves live message objects from
  /// the cached index so seen/expanded/reaction updates avoid full rescans.
  List<ChatThread> get threads {
    _rebuildThreadIndexIfNeeded();
    return [
      for (final rootId in _rootIds)
        ChatThread(
          root: messageById(rootId)!,
          replies: [
            for (final replyId in _replyIdsByTopic[rootId] ?? const <String>[])
              messageById(replyId)!,
          ],
          isRootMissing: messageById(rootId)!.isMissingRoot,
        ),
    ];
  }

  void _markThreadStructureDirty() {
    _threadIndexDirty = true;
  }

  void _commit({bool structure = false}) {
    if (structure) {
      _markThreadStructureDirty();
    }
    notifyListeners();
  }

  void _rebuildThreadIndexIfNeeded() {
    if (!_threadIndexDirty) return;
    _rootIds.clear();
    _replyIdsByTopic.clear();
    _replyIds.clear();
    for (final m in _messages) {
      if (m.isReply) {
        _replyIdsByTopic.putIfAbsent(m.topicId!, () => []).add(m.id);
        _replyIds.add(m.id);
      }
    }
    for (final m in _messages) {
      if (_replyIds.contains(m.id) || m.isReply) continue;
      _rootIds.add(m.id);
    }
    _threadIndexDirty = false;
  }

  bool get isEmpty => _messages.isEmpty;

  bool get hasMessages => _messages.isNotEmpty;

  int indexOfId(String id) => _messages.indexWhere((m) => m.id == id);

  RoomChatMessage? messageById(String id) {
    final i = indexOfId(id);
    return i == -1 ? null : _messages[i];
  }

  void updateLocalIdentity(String identity) {
    if (identity.isNotEmpty) localIdentity = identity;
  }

  void setChatOpen(bool open) {
    if (isChatOpen == open) return;
    isChatOpen = open;
    if (open) {
      markAllSeen();
    } else {
      notifyListeners();
    }
  }

  void setDraftMessage(String text) {
    draftMessage = text;
  }

  // ── Unread badge (includes unseen replies in collapsed threads) ──
  int get unreadCount => _messages.where((m) => !m.seen && !m.isSystem).length;

  // ── New message pill counts root-level new messages only ──
  int unseenRootCount() =>
      _messages.where((m) => !m.seen && !m.isSystem && m.isRoot).length;

  // ── addChatMessages ──
  /// Inserts a message, creating a "missing root" placeholder if this is a
  /// reply whose root is not present locally. Computes seen state.
  /// Returns `true` when [message] was newly inserted (not a duplicate id).
  bool receiveMessage(RoomChatMessage message) {
    if (indexOfId(message.id) != -1) return false;

    if (message.isReply) {
      _ensureMissingRoot(
        rootId: message.topicId!,
        timestamp: message.timestamp,
        topicId: message.topicId,
      );
    }

    _insertChronological(message.copyWith(seen: _computeIncomingSeen(message)));
    _commit(structure: true);
    return true;
  }

  bool _computeIncomingSeen(RoomChatMessage message) {
    if (!isChatOpen) return false;
    if (!message.isReply) return true;
    final root = messageById(message.topicId!);
    final threadHasReplies = _messages.any(
      (m) => m.id != message.topicId && m.topicId == message.topicId,
    );
    return root?.expanded ?? threadHasReplies;
  }

  /// Adds/updates an optimistic local echo (our own outgoing message).
  void addLocalEcho(RoomChatMessage message) {
    final existing = indexOfId(message.id);
    if (existing != -1) {
      _messages[existing] = _messages[existing].withEchoPreservingLocalUi(
        message,
      );
      _commit();
      return;
    }

    if (message.isReply && message.topicId != null) {
      _ensureMissingRoot(
        rootId: message.topicId!,
        timestamp: message.timestamp,
        topicId: message.topicId,
      );
      _setThreadExpanded(message.topicId!, expanded: true, notify: false);
    }

    _insertChronological(message);
    _commit(structure: true);
  }

  void _ensureMissingRoot({
    required String rootId,
    required int timestamp,
    String? topicId,
  }) {
    if (indexOfId(rootId) != -1) return;
    _insertChronological(
      RoomChatMessage.missingRoot(
        rootId: rootId,
        timestamp: timestamp,
        topicId: topicId,
      ),
    );
  }

  /// Adds a plain system (join/leave) notice.
  void addSystemMessage({
    required String id,
    required String message,
    required String identity,
    required String name,
    required int timestamp,
    ChatJoinLeaveKind? joinLeaveKind,
    String? joinLeaveMeetingName,
  }) {
    if (indexOfId(id) != -1) return;
    _insertChronological(
      RoomChatMessage(
        id: id,
        message: message,
        timestamp: timestamp,
        identity: identity,
        name: name,
        seen: isChatOpen,
        isSystem: true,
        joinLeaveKind: joinLeaveKind,
        joinLeaveMeetingName: joinLeaveMeetingName,
      ),
    );
    _commit(structure: true);
  }

  void updateStatus(String id, ChatMessageStatus status) {
    final i = indexOfId(id);
    if (i == -1) return;
    _messages[i] = _messages[i].copyWith(status: status);
    _commit();
  }

  void removeMessage(String id) {
    final removed = _messages.indexWhere((m) => m.id == id);
    if (removed == -1) return;
    _messages.removeAt(removed);
    _reactionIndex.removeWhere((_, ref) => ref.messageId == id);
    _commit(structure: true);
  }

  void markAllSeen() {
    final expandedRootIds = _messages
        .where((m) => m.expanded)
        .map((m) => m.id)
        .toSet();
    var changed = false;
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      final isInCollapsedThread =
          m.isReply && !expandedRootIds.contains(m.topicId);
      if (isInCollapsedThread || m.seen) continue;
      _messages[i] = m.copyWith(seen: true);
      changed = true;
    }
    if (changed) {
      _commit();
    }
  }

  void setThreadExpanded(String rootId, bool expanded) {
    _setThreadExpanded(rootId, expanded: expanded);
  }

  void _setThreadExpanded(
    String rootId, {
    required bool expanded,
    bool notify = true,
  }) {
    final i = indexOfId(rootId);
    if (i == -1 || _messages[i].expanded == expanded) return;

    _messages[i] = _messages[i].copyWith(expanded: expanded);
    if (expanded) {
      _markThreadRepliesSeen(rootId);
    }
    if (notify) {
      _commit();
    }
  }

  void _markThreadRepliesSeen(String rootId) {
    for (var j = 0; j < _messages.length; j++) {
      final m = _messages[j];
      if (m.topicId == rootId && m.id != rootId && !m.seen) {
        _messages[j] = m.copyWith(seen: true);
      }
    }
  }

  void setThreadReplyDraft(String rootId, String? draft) {
    final i = indexOfId(rootId);
    if (i == -1) return;
    _messages[i] = _messages[i].copyWith(
      replyDraft: draft,
      clearReplyDraft: draft == null || draft.isEmpty,
    );
  }

  void addReaction({
    required String reactionId,
    required String messageId,
    required String emoji,
    required String identity,
  }) {
    final i = indexOfId(messageId);
    if (i == -1) return;
    if (emoji.isEmpty || emoji.length > 10) return;

    final m = _messages[i];
    final reactions = cloneReactions(m.reactions);
    final list = reactions.putIfAbsent(emoji, () => <String>[]);
    if (!list.contains(identity)) list.add(identity);

    _messages[i] = m.copyWith(reactions: reactions);
    _reactionIndex[reactionId] = ChatReactionRef(
      messageId: messageId,
      emoji: emoji,
      identity: identity,
    );
    _commit();
  }

  void removeReaction({required String replacesId, required String identity}) {
    final ref = _reactionIndex.remove(replacesId);
    if (ref == null) return;
    if (ref.identity != identity) return;

    final i = indexOfId(ref.messageId);
    if (i == -1) return;

    final m = _messages[i];
    final reactions = cloneReactions(m.reactions);
    final list = reactions[ref.emoji];
    if (list != null) {
      list.remove(identity);
      if (list.isEmpty) reactions.remove(ref.emoji);
    }
    _messages[i] = m.copyWith(reactions: reactions);
    _commit();
  }

  String? findLocalReactionId(String messageId, String emoji) {
    for (final entry in _reactionIndex.entries) {
      final ref = entry.value;
      if (ref.messageId == messageId &&
          ref.emoji == emoji &&
          ref.identity == localIdentity) {
        return entry.key;
      }
    }
    return null;
  }

  bool hasLocalReaction(String messageId, String emoji) {
    final list = messageById(messageId)?.reactions[emoji];
    return list?.contains(localIdentity) ?? false;
  }

  bool isThreadParticipant(ChatThread thread) {
    if (thread.root.identity == localIdentity) return true;
    return thread.replies.any((r) => r.identity == localIdentity);
  }

  bool threadHasUnseenBadge(ChatThread thread) {
    if (!isThreadParticipant(thread)) return false;
    return thread.replies.any((r) => !r.seen);
  }

  void _insertChronological(RoomChatMessage message) {
    var index = _messages.length;
    while (index > 0 && _messages[index - 1].timestamp > message.timestamp) {
      index--;
    }
    _messages.insert(index, message);
    _markThreadStructureDirty();
  }
}

/// Notification-relevance filter: decide whether a message should
/// surface a toast / announcement for the local user.
///
/// Root messages from others always notify. Thread replies notify only when
/// the local user is a thread participant (root author or has replied).
bool isRelevantThreadMessage(
  RoomChatMessage message,
  List<RoomChatMessage> chatMessages,
  String localIdentity,
) {
  if (message.isSystem || message.isMissingRoot) return false;
  if (localIdentity.isNotEmpty && message.identity == localIdentity) {
    return false;
  }

  if (!message.isReply) return true;

  final topicId = message.topicId;
  if (topicId == null) return false;

  return chatMessages.any(
    (m) =>
        (m.id == topicId || m.topicId == topicId) &&
        m.identity == localIdentity,
  );
}
