/// Local UI models for Meet chat threads + MimiV1 reactions.
///
/// Mirrors the data model described in the "Chat Threads in Meet" spec
/// (MEET-1229). All encryption / wire framing happens in meet-core; these
/// structures only hold the decoded, structured state consumed by the UI.
library;

/// Local send status for a chat message (only meaningful for the local sender).
enum ChatMessageStatus { pending, sent, failed }

/// Join/leave system notice variant (rendered with localized prefix + meeting name).
enum ChatJoinLeaveKind { joined, left }

/// A single chat message in the local store.
///
/// Covers root messages, thread replies, "missing root" placeholders and
/// synthetic system (join/leave) notices.
class RoomChatMessage {
  RoomChatMessage({
    required this.id,
    required this.message,
    required this.timestamp,
    required this.identity,
    required this.name,
    this.seen = false,
    this.inReplyToId,
    this.topicId,
    this.status,
    this.expanded = false,
    this.replyDraft,
    this.isMissingRoot = false,
    this.isSystem = false,
    this.joinLeaveKind,
    this.joinLeaveMeetingName,
    Map<String, List<String>>? reactions,
  }) : reactions = reactions ?? <String, List<String>>{};

  /// Globally unique id, assigned by meet-core at compose time (hex for MimiV1).
  final String id;

  /// Sanitized plaintext.
  final String message;

  /// received_at_ms.
  final int timestamp;

  /// sender_participant_id (MLS participant UUID).
  final String identity;

  /// Resolved display name of the sender (local-only).
  final String name;

  /// Local read state (never transmitted).
  bool seen;

  // ── Thread fields (wire + local) ──
  /// Message id this reply directly responds to (usually the root id).
  final String? inReplyToId;

  /// Thread root id. For a reply, `topicId != id`.
  final String? topicId;

  // ── Local-only UI state ──
  /// pending / sent / failed (local sender only).
  ChatMessageStatus? status;

  /// Root only: whether the thread is expanded.
  bool expanded;

  /// Root only: persisted thread reply draft.
  String? replyDraft;

  /// Placeholder root created when the real root was never received.
  final bool isMissingRoot;

  /// Synthetic system message (join/leave), rendered differently.
  final bool isSystem;

  /// When set, [message] body is built from l10n prefix + [joinLeaveMeetingName].
  final ChatJoinLeaveKind? joinLeaveKind;

  /// Meeting name highlighted in join/leave system notices.
  final String? joinLeaveMeetingName;

  // ── Reactions (aggregated from Reaction events) ──
  /// emoji → [participantIdentity, ...]
  final Map<String, List<String>> reactions;

  /// True when this message opens a thread (top-level / not a reply).
  bool get isRoot => topicId == null || topicId == id;

  /// True when this message is a reply within a thread.
  bool get isReply => topicId != null && topicId != id;

  bool get hasReactions => reactions.values.any((l) => l.isNotEmpty);

  RoomChatMessage copyWith({
    bool? seen,
    ChatMessageStatus? status,
    bool? expanded,
    String? replyDraft,
    bool clearReplyDraft = false,
    ChatJoinLeaveKind? joinLeaveKind,
    String? joinLeaveMeetingName,
    Map<String, List<String>>? reactions,
  }) {
    return RoomChatMessage(
      id: id,
      message: message,
      timestamp: timestamp,
      identity: identity,
      name: name,
      seen: seen ?? this.seen,
      inReplyToId: inReplyToId,
      topicId: topicId,
      status: status ?? this.status,
      expanded: expanded ?? this.expanded,
      replyDraft: clearReplyDraft ? null : (replyDraft ?? this.replyDraft),
      isMissingRoot: isMissingRoot,
      isSystem: isSystem,
      joinLeaveKind: joinLeaveKind ?? this.joinLeaveKind,
      joinLeaveMeetingName: joinLeaveMeetingName ?? this.joinLeaveMeetingName,
      reactions: reactions ?? cloneReactions(this.reactions),
    );
  }
}

/// Deep-copies an emoji → identities reaction map.
Map<String, List<String>> cloneReactions(Map<String, List<String>> source) {
  return source.map((k, v) => MapEntry(k, List<String>.from(v)));
}

/// Reverse index entry: original reaction event id → what it reacted to.
///
/// Needed so the local participant can `composeChatUnreact` with the original
/// reaction event id when toggling the same emoji off.
class ChatReactionRef {
  const ChatReactionRef({
    required this.messageId,
    required this.emoji,
    required this.identity,
  });

  final String messageId;
  final String emoji;
  final String identity;
}

/// A grouped thread for rendering the main chat list.
class ChatThread {
  const ChatThread({
    required this.root,
    required this.replies,
    required this.isRootMissing,
  });

  final RoomChatMessage root;
  final List<RoomChatMessage> replies;
  final bool isRootMissing;

  bool get hasReplies => replies.isNotEmpty;
}
