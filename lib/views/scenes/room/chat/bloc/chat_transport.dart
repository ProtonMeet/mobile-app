import 'package:livekit_client/livekit_client.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/rust/proton_meet/core.dart';
import 'package:meet/rust/proton_meet/models/chat_event.dart';

/// A composed outgoing chat event: the wire [payload] to publish, plus the
/// optimistic local echo meet-core assigned to it.
class ComposedChatEvent {
  const ComposedChatEvent({
    required this.payload,
    required this.id,
    required this.senderParticipantId,
    required this.receivedAtMs,
    this.text,
    this.inReplyToId,
    this.topicId,
  });

  final List<int> payload;
  final String id;
  final String senderParticipantId;
  final int receivedAtMs;
  final String? text;
  final String? inReplyToId;
  final String? topicId;
}

/// The wire side of chat: composing encrypted payloads in meet-core and
/// publishing them on the data channel.
///
/// [ChatBloc] talks to chat only through this interface, so it can be unit
/// tested without a LiveKit room or the Rust bridge.
abstract interface class ChatTransport {
  /// Local participant identity (MLS sender id), or empty when the room has no
  /// local participant yet.
  String get localIdentity;

  Future<ComposedChatEvent> composeMessage({
    required String text,
    String? replyToId,
    String? topicId,
  });

  Future<ComposedChatEvent> composeReaction({
    required String targetId,
    required String emoji,
  });

  Future<ComposedChatEvent> composeUnreact({
    required String targetId,
    required String replacesId,
  });

  /// A single publish attempt. Returns false when it failed; the retry policy
  /// belongs to the caller.
  Future<bool> publish(List<int> payload);
}

/// Production transport: composes through meet-core, publishes on the current
/// LiveKit room.
///
/// Both dependencies are read through callbacks on every call so the transport
/// keeps working after a rejoin replaces the [Room] or the [AppCore] instance.
class AppCoreChatTransport implements ChatTransport {
  AppCoreChatTransport({
    required AppCore Function() appCore,
    required Room Function() room,
  }) : _appCore = appCore,
       _room = room;

  final AppCore Function() _appCore;
  final Room Function() _room;

  @override
  String get localIdentity => _room().localParticipant?.identity ?? '';

  @override
  Future<ComposedChatEvent> composeMessage({
    required String text,
    String? replyToId,
    String? topicId,
  }) async {
    final result = await _appCore().composeChatMessage(
      text: text,
      replyToId: replyToId,
      replyTopicId: topicId,
    );
    return _toComposed(result);
  }

  @override
  Future<ComposedChatEvent> composeReaction({
    required String targetId,
    required String emoji,
  }) async {
    final result = await _appCore().composeChatReaction(
      targetId: targetId,
      emoji: emoji,
    );
    return _toComposed(result);
  }

  @override
  Future<ComposedChatEvent> composeUnreact({
    required String targetId,
    required String replacesId,
  }) async {
    final result = await _appCore().composeChatUnreact(
      targetId: targetId,
      replacesId: replacesId,
    );
    return _toComposed(result);
  }

  @override
  Future<bool> publish(List<int> payload) async {
    final local = _room().localParticipant;
    if (local == null) {
      return false;
    }
    try {
      await local.publishData(payload, reliable: true);
      return true;
    } catch (e) {
      l.logger.w('[ChatTransport] publishData failed: $e');
      return false;
    }
  }

  ComposedChatEvent _toComposed(FrbChatComposeResult result) {
    final echo = result.localEcho;
    return ComposedChatEvent(
      payload: result.payload,
      id: echo.id,
      senderParticipantId: echo.senderParticipantId,
      receivedAtMs: echo.receivedAtMs.toInt(),
      text: echo.text,
      inReplyToId: echo.inReplyToId,
      topicId: echo.topicId,
    );
  }
}
