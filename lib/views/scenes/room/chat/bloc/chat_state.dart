import 'package:equatable/equatable.dart';
import 'package:meet/views/scenes/room/chat/chat_models.dart';

/// Everything the UI needs to know about chat, and nothing else.
///
/// [revision] is what makes this comparable: [RoomChatMessage] carries mutable
/// local UI fields (seen, expanded, drafts), so deep equality on [messages]
/// would be both expensive and unreliable. The bloc bumps [revision] on every
/// committed change instead, and widgets narrow to the field they care about
/// with `BlocSelector` so a new revision does not rebuild the whole room.
class ChatState extends Equatable {
  const ChatState({
    this.revision = 0,
    this.isPanelOpen = false,
    this.unreadCount = 0,
    this.unseenRootCount = 0,
    this.localIdentity = '',
    this.messages = const [],
  });

  /// Monotonic version of the chat transcript.
  final int revision;

  /// Whether the chat panel is currently visible.
  final bool isPanelOpen;

  /// Unseen, non-system messages, including replies in collapsed threads.
  final int unreadCount;

  /// Unseen root-level messages only; drives the "new messages" pill.
  final int unseenRootCount;

  /// Local participant identity, empty until the room reports one.
  final String localIdentity;

  /// Chronological transcript snapshot (oldest to newest).
  final List<RoomChatMessage> messages;

  bool get hasUnread => unreadCount > 0;

  @override
  List<Object?> get props => [
    revision,
    isPanelOpen,
    unreadCount,
    unseenRootCount,
    localIdentity,
  ];
}
