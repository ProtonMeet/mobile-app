import 'package:equatable/equatable.dart';
import 'package:meet/views/scenes/room/chat/chat_models.dart';

/// Everything the chat feature can be asked to do.
///
/// Sealed so a new case forces every `switch` over chat intents to be updated,
/// unlike the flat `RoomBlocEvent` hierarchy where a chat event could be
/// dispatched with no handler and silently do nothing.
sealed class ChatEvent extends Equatable {
  const ChatEvent();

  @override
  List<Object?> get props => const [];
}

/// The transcript changed underneath the bloc.
///
/// Dispatched by [ChatBloc]'s own listener on [ChatController] so mutations
/// made straight from the widget layer (expanding a thread, editing a reply
/// draft) still produce a fresh [ChatState]. Not for outside use.
class ChatTranscriptChanged extends ChatEvent {
  const ChatTranscriptChanged();
}

/// The chat panel was opened or closed. Drives seen/unread accounting and
/// whether incoming messages raise a toast.
class ChatPanelVisibilityChanged extends ChatEvent {
  const ChatPanelVisibilityChanged({required this.isOpen});

  final bool isOpen;

  @override
  List<Object?> get props => [isOpen];
}

/// The local participant identity became known (or changed after a rejoin).
class ChatLocalIdentityChanged extends ChatEvent {
  const ChatLocalIdentityChanged(this.identity);

  final String identity;

  @override
  List<Object?> get props => [identity];
}

/// The local user submitted a message. [topicId]/[replyToId] make it a reply.
class ChatMessageSubmitted extends ChatEvent {
  const ChatMessageSubmitted({
    required this.text,
    required this.senderDisplayName,
    this.replyToId,
    this.topicId,
  });

  final String text;
  final String senderDisplayName;
  final String? replyToId;
  final String? topicId;

  @override
  List<Object?> get props => [text, senderDisplayName, replyToId, topicId];
}

/// Retry a message that failed to publish, preserving its thread position.
class ChatMessageRetryRequested extends ChatEvent {
  const ChatMessageRetryRequested({
    required this.messageId,
    required this.text,
    required this.senderDisplayName,
    this.replyToId,
    this.topicId,
  });

  final String messageId;
  final String text;
  final String senderDisplayName;
  final String? replyToId;
  final String? topicId;

  @override
  List<Object?> get props => [
    messageId,
    text,
    senderDisplayName,
    replyToId,
    topicId,
  ];
}

/// Drop a message from the local store (used to discard a failed send).
class ChatMessageDiscarded extends ChatEvent {
  const ChatMessageDiscarded(this.messageId);

  final String messageId;

  @override
  List<Object?> get props => [messageId];
}

/// The local user tapped an emoji on [messageId]. The bloc decides whether
/// that means react or unreact by looking up its own reaction index.
class ChatReactionToggled extends ChatEvent {
  const ChatReactionToggled({required this.messageId, required this.emoji});

  final String messageId;
  final String emoji;

  @override
  List<Object?> get props => [messageId, emoji];
}

/// A chat message arrived from a remote participant (MimiV1 or legacy).
class ChatMessageReceived extends ChatEvent {
  const ChatMessageReceived({
    required this.id,
    required this.message,
    required this.timestamp,
    required this.identity,
    required this.name,
    this.inReplyToId,
    this.topicId,
    this.notify = false,
  });

  final String id;
  final String message;
  final int timestamp;
  final String identity;
  final String name;
  final String? inReplyToId;
  final String? topicId;

  /// Whether the caller wants a toast when this message turns out to be new,
  /// unseen and relevant. The bloc applies those conditions itself.
  final bool notify;

  @override
  List<Object?> get props => [
    id,
    message,
    timestamp,
    identity,
    name,
    inReplyToId,
    topicId,
    notify,
  ];
}

/// A reaction arrived from a remote participant. [replacesId] set means the
/// sender withdrew an earlier reaction.
class ChatReactionReceived extends ChatEvent {
  const ChatReactionReceived({
    required this.reactionId,
    required this.senderIdentity,
    this.replacesId,
    this.targetId,
    this.emoji,
  });

  final String reactionId;
  final String senderIdentity;
  final String? replacesId;
  final String? targetId;
  final String? emoji;

  @override
  List<Object?> get props => [
    reactionId,
    senderIdentity,
    replacesId,
    targetId,
    emoji,
  ];
}

/// A join/leave or lifecycle notice to render inline in the chat transcript.
class ChatSystemNoticeAdded extends ChatEvent {
  const ChatSystemNoticeAdded({
    required this.message,
    required this.identity,
    required this.name,
    this.joinLeaveKind,
    this.meetingName,
  });

  final String message;
  final String identity;
  final String name;
  final ChatJoinLeaveKind? joinLeaveKind;
  final String? meetingName;

  @override
  List<Object?> get props => [
    message,
    identity,
    name,
    joinLeaveKind,
    meetingName,
  ];
}
