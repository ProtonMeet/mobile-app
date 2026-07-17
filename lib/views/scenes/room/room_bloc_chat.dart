import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/views/scenes/room/chat/chat_models.dart';

import 'room_event.dart';
import 'room_state.dart';

mixin RoomChatHandlers on Bloc<RoomBlocEvent, RoomState> {
  static const int _joinLeaveChatSuppressThreshold = 50;

  void registerChatHandlers() {
    on<AddSystemMessage>(_onAddSystemMessageReceived);
    on<SendChatMessage>(_onSendChatMessage);
    on<ToggleChatReaction>(_onToggleChatReaction);
    on<ReceiveChatTextMessage>(_onReceiveChatTextMessage);
    on<ReceiveMimiChatMessage>(_onReceiveMimiChatMessage);
    on<ReceiveMimiChatReaction>(_onReceiveMimiChatReaction);
    on<RemoveChatMessage>(_onRemoveChatMessage);
    on<RoomMessageReceived>(_onRoomMessageReceived);
    on<ChatBlocOutputsConsumed>(_onChatBlocOutputsConsumed);
  }

  bool _isMeetNewChatHandling() => ManagerFactory()
      .get<DataProviderManager>()
      .unleashDataProvider
      .isMeetNewChatHandling();

  AppCoreManager get _appCoreManager => ManagerFactory().get<AppCoreManager>();

  void _appendChatEffect(RoomChatEffect effect, Emitter<RoomState> emit) {
    emit(
      state.copyWith(
        chatEffects: [...state.chatEffects, effect],
        chatSyncGeneration: state.chatSyncGeneration + 1,
      ),
    );
  }

  void _onChatBlocOutputsConsumed(
    ChatBlocOutputsConsumed event,
    Emitter<RoomState> emit,
  ) {
    if (state.chatEffects.isEmpty && state.chatSystemNotices.isEmpty) return;
    emit(
      state.copyWith(
        chatEffects: const [],
        chatSystemNotices: const [],
      ),
    );
  }

  Future<bool> _publishWithRetry(List<int> payload) async {
    const delaysMs = [0, 2000, 5000];
    final local = state.room.localParticipant;
    if (local == null) return false;
    for (final delay in delaysMs) {
      if (delay > 0) {
        await Future<void>.delayed(Duration(milliseconds: delay));
      }
      try {
        await local.publishData(payload, reliable: true);
        return true;
      } catch (e) {
        l.logger.w('[RoomChatHandlers] publishData failed (retrying): $e');
      }
    }
    return false;
  }

  void _onAddSystemMessageReceived(
    AddSystemMessage event,
    Emitter<RoomState> emit,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final isJoinLeaveSystemMessage = event.joinLeaveKind != null;
    final isLargeRoom =
        state.participantTracks.length >= _joinLeaveChatSuppressThreshold ||
        state.participantsCount >= _joinLeaveChatSuppressThreshold;

    if (isJoinLeaveSystemMessage && isLargeRoom) {
      return;
    }

    if (event.logLevel != Level.info) {
      return;
    }

    final notice = RoomChatSystemNotice(
      id: '${event.identity}-$now-${DateTime.now().microsecondsSinceEpoch}',
      message: event.message,
      identity: event.identity,
      name: event.name,
      timestamp: now,
      joinLeaveKind: event.joinLeaveKind,
      meetingName: event.meetingName,
    );
    emit(
      state.copyWith(
        chatSystemNotices: [...state.chatSystemNotices, notice],
        chatSyncGeneration: state.chatSyncGeneration + 1,
      ),
    );
  }

  Future<void> _onSendChatMessage(
    SendChatMessage event,
    Emitter<RoomState> emit,
  ) async {
    if (!_isMeetNewChatHandling()) return;

    final trimmed = event.text.trim();
    if (trimmed.isEmpty) return;

    final localId = state.room.localParticipant?.identity ?? '';
    try {
      final result = await _appCoreManager.appCore.composeChatMessage(
        text: trimmed,
        replyToId: event.replyToId,
        replyTopicId: event.topicId,
      );
      final echo = result.localEcho;
      _appendChatEffect(
        RoomChatEffect(
          kind: RoomChatEffectKind.localEcho,
          messagePayload: RoomChatMessage(
            id: echo.id,
            message: echo.text ?? trimmed,
            timestamp: echo.receivedAtMs.toInt(),
            identity: localId.isEmpty ? echo.senderParticipantId : localId,
            name: event.localDisplayName,
            seen: true,
            inReplyToId: echo.inReplyToId,
            topicId: echo.topicId,
            status: ChatMessageStatus.pending,
          ),
        ),
        emit,
      );
      final ok = await _publishWithRetry(result.payload);
      _appendChatEffect(
        RoomChatEffect(
          kind: RoomChatEffectKind.updateMessageStatus,
          messageId: echo.id,
          status: ok ? ChatMessageStatus.sent : ChatMessageStatus.failed,
        ),
        emit,
      );
    } catch (e) {
      l.logger.e('[RoomChatHandlers] composeChatMessage failed: $e');
      _appendChatEffect(
        RoomChatEffect(
          kind: RoomChatEffectKind.localEcho,
          messagePayload: RoomChatMessage(
            id: 'local-failed-${DateTime.now().microsecondsSinceEpoch}',
            message: trimmed,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            identity: localId,
            name: event.localDisplayName,
            seen: true,
            inReplyToId: event.replyToId,
            topicId: event.topicId,
            status: ChatMessageStatus.failed,
          ),
        ),
        emit,
      );
    }
  }

  Future<void> _onToggleChatReaction(
    ToggleChatReaction event,
    Emitter<RoomState> emit,
  ) async {
    if (!_isMeetNewChatHandling()) return;

    final localId = state.room.localParticipant?.identity ?? '';
    try {
      if (event.existingReactionId != null) {
        final existingReactionId = event.existingReactionId!;
        final result = await _appCoreManager.appCore.composeChatUnreact(
          targetId: event.messageId,
          replacesId: existingReactionId,
        );
        _appendChatEffect(
          RoomChatEffect(
            kind: RoomChatEffectKind.removeReaction,
            replacesId: existingReactionId,
            identity: localId,
          ),
          emit,
        );
        final ok = await _publishWithRetry(result.payload);
        if (!ok) {
          _appendChatEffect(
            RoomChatEffect(
              kind: RoomChatEffectKind.addReaction,
              reactionId: existingReactionId,
              messageId: event.messageId,
              emoji: event.emoji,
              identity: localId,
            ),
            emit,
          );
        }
      } else {
        final result = await _appCoreManager.appCore.composeChatReaction(
          targetId: event.messageId,
          emoji: event.emoji,
        );
        final reactionId = result.localEcho.id;
        _appendChatEffect(
          RoomChatEffect(
            kind: RoomChatEffectKind.addReaction,
            reactionId: reactionId,
            messageId: event.messageId,
            emoji: event.emoji,
            identity: localId,
          ),
          emit,
        );
        final ok = await _publishWithRetry(result.payload);
        if (!ok) {
          _appendChatEffect(
            RoomChatEffect(
              kind: RoomChatEffectKind.removeReaction,
              replacesId: reactionId,
              identity: localId,
            ),
            emit,
          );
        }
      }
    } catch (e) {
      l.logger.e('[RoomChatHandlers] toggleChatReaction failed: $e');
    }
  }

  void _onReceiveChatTextMessage(
    ReceiveChatTextMessage event,
    Emitter<RoomState> emit,
  ) {
    _appendChatEffect(
      RoomChatEffect(
        kind: RoomChatEffectKind.receiveMessage,
        showToast: event.showToast,
        messagePayload: RoomChatMessage(
          id: event.id,
          message: event.message,
          timestamp: event.timestamp,
          identity: event.identity,
          name: event.name,
        ),
      ),
      emit,
    );
  }

  void _onReceiveMimiChatMessage(
    ReceiveMimiChatMessage event,
    Emitter<RoomState> emit,
  ) {
    _appendChatEffect(
      RoomChatEffect(
        kind: RoomChatEffectKind.receiveMessage,
        showToast: event.showToast,
        messagePayload: RoomChatMessage(
          id: event.id,
          message: event.message,
          timestamp: event.timestamp,
          identity: event.identity,
          name: event.name,
          inReplyToId: event.inReplyToId,
          topicId: event.topicId,
        ),
      ),
      emit,
    );
  }

  void _onReceiveMimiChatReaction(
    ReceiveMimiChatReaction event,
    Emitter<RoomState> emit,
  ) {
    if (event.replacesId != null) {
      _appendChatEffect(
        RoomChatEffect(
          kind: RoomChatEffectKind.removeReaction,
          replacesId: event.replacesId,
          identity: event.senderIdentity,
        ),
        emit,
      );
      return;
    }

    final targetId = event.targetId;
    final emoji = event.emoji;
    if (targetId == null || emoji == null || emoji.length > 10) return;

    _appendChatEffect(
      RoomChatEffect(
        kind: RoomChatEffectKind.addReaction,
        reactionId: event.reactionId,
        messageId: targetId,
        emoji: emoji,
        identity: event.senderIdentity,
      ),
      emit,
    );
  }

  void _onRemoveChatMessage(
    RemoveChatMessage event,
    Emitter<RoomState> emit,
  ) {
    _appendChatEffect(
      RoomChatEffect(
        kind: RoomChatEffectKind.removeMessage,
        messageId: event.messageId,
      ),
      emit,
    );
  }

  void _onRoomMessageReceived(
    RoomMessageReceived event,
    Emitter<RoomState> emit,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _appendChatEffect(
      RoomChatEffect(
        kind: RoomChatEffectKind.receiveMessage,
        messagePayload: RoomChatMessage(
          id: '${event.identity}-$now',
          message: event.message,
          timestamp: now,
          identity: event.identity,
          name: event.name,
        ),
      ),
      emit,
    );
  }
}
