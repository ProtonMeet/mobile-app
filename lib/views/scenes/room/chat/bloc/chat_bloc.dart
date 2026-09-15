import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/views/scenes/room/chat/bloc/chat_event.dart';
import 'package:meet/views/scenes/room/chat/bloc/chat_state.dart';
import 'package:meet/views/scenes/room/chat/bloc/chat_transport.dart';
import 'package:meet/views/scenes/room/chat/chat_controller.dart';
import 'package:meet/views/scenes/room/chat/chat_models.dart';

/// Owns the in-meeting chat transcript for the lifetime of a call.
///
/// This is the only writer of chat state. The transcript itself lives in
/// [ChatController], which acts as the reducer over messages, threads,
/// reactions and seen state; the bloc drives it, publishes to the wire through
/// [ChatTransport], and emits a [ChatState] snapshot for the UI.
///
/// Every dependency is injected, so the whole feature — optimistic echoes,
/// publish retries, reaction rollback, unread accounting, toast relevance —
/// is testable without a LiveKit room, the Rust bridge, or a widget tree.
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  ChatBloc({
    required ChatTransport transport,
    required bool Function() isThreadedChatEnabled,
    required int Function() participantCount,
    ChatController? controller,
    List<Duration> publishRetryDelays = defaultPublishRetryDelays,
  }) : _transport = transport,
       _isThreadedChatEnabled = isThreadedChatEnabled,
       _participantCount = participantCount,
       _publishRetryDelays = publishRetryDelays,
       _ownsController = controller == null,
       controller = controller ?? ChatController(localIdentity: ''),
       super(const ChatState()) {
    on<ChatTranscriptChanged>((_, emit) => _emitSnapshot(emit));
    on<ChatPanelVisibilityChanged>(_onPanelVisibilityChanged);
    on<ChatLocalIdentityChanged>(_onLocalIdentityChanged);
    on<ChatMessageSubmitted>(
      _onMessageSubmitted,
      transformer: (events, mapper) => events.asyncExpand(mapper),
    );
    on<ChatMessageRetryRequested>(_onMessageRetryRequested);
    on<ChatMessageDiscarded>(_onMessageDiscarded);
    on<ChatReactionToggled>(
      _onReactionToggled,
      transformer: (events, mapper) => events.asyncExpand(mapper),
    );
    on<ChatMessageReceived>(_onMessageReceived);
    on<ChatReactionReceived>(_onReactionReceived);
    on<ChatSystemNoticeAdded>(_onSystemNoticeAdded);

    // Covers transcript mutations the widget layer still makes directly.
    this.controller.addListener(_onControllerChanged);
  }

  /// Publish attempt schedule. MLS may not be ready when the first attempt
  /// runs, so a failed publish is retried rather than dropped.
  static const List<Duration> defaultPublishRetryDelays = [
    Duration.zero,
    Duration(seconds: 2),
    Duration(seconds: 5),
  ];

  /// Above this many participants, join/leave notices are suppressed: in large
  /// meetings they drown out real messages.
  static const int joinLeaveSuppressThreshold = 50;

  /// Reducer for the transcript.
  ///
  /// Exposed because [ChatWidget] still renders directly off the controller.
  /// Reads are safe; nothing outside this bloc should mutate it.
  final ChatController controller;
  final bool _ownsController;

  final ChatTransport _transport;
  final bool Function() _isThreadedChatEnabled;
  final int Function() _participantCount;
  final List<Duration> _publishRetryDelays;

  final StreamController<RoomChatMessage> _toasts =
      StreamController<RoomChatMessage>.broadcast();

  int _revision = 0;

  /// Messages that should surface a toast: new, from someone else, relevant to
  /// the local user, and arriving while the panel is closed.
  ///
  /// A stream rather than a state field because a toast is a one-shot effect;
  /// putting it in state would need a "consumed" event to clear it.
  Stream<RoomChatMessage> get incomingMessageToasts => _toasts.stream;

  /// Resolves the local sender id, adopting the transport's value when the
  /// controller has not been told one yet.
  ///
  /// The controller stays the single owner: attributing a reaction to an
  /// identity it does not consider local would break
  /// [ChatController.findLocalReactionId], so a later un-react would compose a
  /// duplicate reaction instead of withdrawing the original.
  String _resolveLocalIdentity() {
    final fromTransport = _transport.localIdentity;
    if (fromTransport.isNotEmpty && controller.localIdentity != fromTransport) {
      controller.updateLocalIdentity(fromTransport);
    }
    return controller.localIdentity;
  }

  void _onPanelVisibilityChanged(
    ChatPanelVisibilityChanged event,
    Emitter<ChatState> emit,
  ) {
    if (controller.isChatOpen == event.isOpen) {
      return;
    }
    controller.setChatOpen(open: event.isOpen);
  }

  void _onLocalIdentityChanged(
    ChatLocalIdentityChanged event,
    Emitter<ChatState> emit,
  ) {
    if (event.identity.isEmpty || controller.localIdentity == event.identity) {
      return;
    }
    controller.updateLocalIdentity(event.identity);
  }

  Future<void> _onMessageSubmitted(
    ChatMessageSubmitted event,
    Emitter<ChatState> emit,
  ) async {
    await _send(
      text: event.text,
      senderDisplayName: event.senderDisplayName,
      replyToId: event.replyToId,
      topicId: event.topicId,
    );
  }

  Future<void> _onMessageRetryRequested(
    ChatMessageRetryRequested event,
    Emitter<ChatState> emit,
  ) async {
    controller.removeMessage(event.messageId);
    await _send(
      text: event.text,
      senderDisplayName: event.senderDisplayName,
      replyToId: event.replyToId,
      topicId: event.topicId,
    );
  }

  void _onMessageDiscarded(
    ChatMessageDiscarded event,
    Emitter<ChatState> emit,
  ) {
    controller.removeMessage(event.messageId);
  }

  Future<void> _send({
    required String text,
    required String senderDisplayName,
    required String? replyToId,
    required String? topicId,
  }) async {
    if (!_isThreadedChatEnabled()) {
      return;
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }

    final localId = _resolveLocalIdentity();
    try {
      final composed = await _transport.composeMessage(
        text: trimmed,
        replyToId: replyToId,
        topicId: topicId,
      );
      if (isClosed) {
        return;
      }
      controller.addLocalEcho(
        RoomChatMessage(
          id: composed.id,
          message: composed.text ?? trimmed,
          timestamp: composed.receivedAtMs,
          identity: localId.isEmpty ? composed.senderParticipantId : localId,
          name: senderDisplayName,
          seen: true,
          inReplyToId: composed.inReplyToId,
          topicId: composed.topicId,
          status: ChatMessageStatus.pending,
        ),
      );

      final published = await _publishWithRetry(composed.payload);
      if (isClosed) {
        return;
      }
      controller.updateStatus(
        composed.id,
        published ? ChatMessageStatus.sent : ChatMessageStatus.failed,
      );
    } catch (e) {
      l.logger.e('[ChatBloc] composing message failed: $e');
      if (isClosed) {
        return;
      }
      // Surface the failure in the transcript so the user can retry rather
      // than losing what they typed.
      controller.addLocalEcho(
        RoomChatMessage(
          id: 'local-failed-${DateTime.now().microsecondsSinceEpoch}',
          message: trimmed,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          identity: localId,
          name: senderDisplayName,
          seen: true,
          inReplyToId: replyToId,
          topicId: topicId,
          status: ChatMessageStatus.failed,
        ),
      );
    }
  }

  Future<void> _onReactionToggled(
    ChatReactionToggled event,
    Emitter<ChatState> emit,
  ) async {
    if (!_isThreadedChatEnabled()) {
      return;
    }

    final localId = _resolveLocalIdentity();
    final existingReactionId = controller.findLocalReactionId(
      event.messageId,
      event.emoji,
    );

    try {
      if (existingReactionId != null) {
        final composed = await _transport.composeUnreact(
          targetId: event.messageId,
          replacesId: existingReactionId,
        );
        if (isClosed) {
          return;
        }
        controller.removeReaction(
          replacesId: existingReactionId,
          identity: localId,
        );

        if (!await _publishWithRetry(composed.payload)) {
          if (isClosed) {
            return;
          }
          controller.addReaction(
            reactionId: existingReactionId,
            messageId: event.messageId,
            emoji: event.emoji,
            identity: localId,
          );
        }
        return;
      }

      final composed = await _transport.composeReaction(
        targetId: event.messageId,
        emoji: event.emoji,
      );
      if (isClosed) {
        return;
      }
      controller.addReaction(
        reactionId: composed.id,
        messageId: event.messageId,
        emoji: event.emoji,
        identity: localId,
      );

      if (!await _publishWithRetry(composed.payload)) {
        if (isClosed) {
          return;
        }
        controller.removeReaction(replacesId: composed.id, identity: localId);
      }
    } catch (e) {
      l.logger.e('[ChatBloc] toggling reaction failed: $e');
    }
  }

  void _onMessageReceived(ChatMessageReceived event, Emitter<ChatState> emit) {
    final message = RoomChatMessage(
      id: event.id,
      message: event.message,
      timestamp: event.timestamp,
      identity: event.identity,
      name: event.name,
      inReplyToId: event.inReplyToId,
      topicId: event.topicId,
    );

    final isNew = controller.receiveMessage(message);
    if (!isNew) {
      return;
    }

    if (!event.notify || controller.isChatOpen) {
      return;
    }
    if (!isRelevantThreadMessage(
      message,
      controller.messages,
      _resolveLocalIdentity(),
    )) {
      return;
    }
    _toasts.add(message);
  }

  void _onReactionReceived(
    ChatReactionReceived event,
    Emitter<ChatState> emit,
  ) {
    final replacesId = event.replacesId;
    if (replacesId != null) {
      controller.removeReaction(
        replacesId: replacesId,
        identity: event.senderIdentity,
      );
      return;
    }

    final targetId = event.targetId;
    final emoji = event.emoji;
    if (targetId == null ||
        emoji == null ||
        emoji.isEmpty ||
        emoji.length > 10) {
      return;
    }
    controller.addReaction(
      reactionId: event.reactionId,
      messageId: targetId,
      emoji: emoji,
      identity: event.senderIdentity,
    );
  }

  void _onSystemNoticeAdded(
    ChatSystemNoticeAdded event,
    Emitter<ChatState> emit,
  ) {
    final isJoinLeave = event.joinLeaveKind != null;
    if (isJoinLeave && _participantCount() >= joinLeaveSuppressThreshold) {
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    controller.addSystemMessage(
      id: '${event.identity}-$now-${DateTime.now().microsecondsSinceEpoch}',
      message: event.message,
      identity: event.identity,
      name: event.name,
      timestamp: now,
      joinLeaveKind: event.joinLeaveKind,
      joinLeaveMeetingName: event.meetingName,
    );
  }

  Future<bool> _publishWithRetry(List<int> payload) async {
    for (final delay in _publishRetryDelays) {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      if (isClosed) {
        return false;
      }
      if (await _transport.publish(payload)) {
        return true;
      }
      l.logger.w('[ChatBloc] publish attempt failed, retrying');
    }
    return false;
  }

  void _emitSnapshot(Emitter<ChatState> emit) {
    if (isClosed) {
      return;
    }
    emit(
      ChatState(
        revision: ++_revision,
        isPanelOpen: controller.isChatOpen,
        unreadCount: controller.unreadCount,
        unseenRootCount: controller.unseenRootCount(),
        localIdentity: controller.localIdentity,
        messages: controller.messages,
      ),
    );
  }

  void _onControllerChanged() {
    if (isClosed) {
      return;
    }
    add(const ChatTranscriptChanged());
  }

  @override
  Future<void> close() async {
    controller.removeListener(_onControllerChanged);
    await super.close();
    await _toasts.close();
    if (_ownsController) {
      controller.dispose();
    }
  }
}
