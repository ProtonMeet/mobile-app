import 'dart:async';
import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/constants/live_captions_constants.dart';
import 'package:meet/helper/live_captions/live_caption_decrypt.dart';
import 'package:meet/helper/live_captions/live_captions_clipboard.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/models/live_captions/live_caption_agent.dart';
import 'package:meet/models/live_captions/live_caption_text_stream.dart';
import 'package:meet/models/live_captions/live_captions_models.dart';
import 'package:meet/models/live_captions/live_captions_transcription_store.dart';
import 'package:meet/rust/proton_meet/models/meet_participant.dart';

import 'room_bloc_feature_flags.dart';
import 'room_event.dart';
import 'room_state.dart';

/// Registers the `lk.transcription` text stream handler, decrypts MLS payloads,
/// and keeps [RoomState.liveCaptionsTranscriptions] in sync.
mixin RoomLiveCaptionsTranscriptionHandlers
    on Bloc<RoomBlocEvent, RoomState>, RoomFeatureFlagsHandlers {
  static final Set<Object> _roomsWithTranscriptionConsumer = {};

  final LiveCaptionsTranscriptionStore _liveCaptionsStore =
      LiveCaptionsTranscriptionStore();
  TranscriptionDiagnostics _liveCaptionsDiagnostics =
      TranscriptionDiagnostics();
  bool _liveCaptionsListening = false;
  bool _liveCaptionsFailing = false;
  Room? _liveCaptionsHandlerRoom;
  Timer? _liveCaptionsExpiryTimer;
  Timer? _liveCaptionsReadyTimeoutTimer;

  AppCoreManager get _appCoreManager => ManagerFactory().get<AppCoreManager>();

  bool get hasLiveCaptionsHistory => !_liveCaptionsStore.historyIsEmpty;

  String formatLiveCaptionsHistoryForClipboard(
    Map<String, MeetParticipant> participantNamesByIdentity,
  ) {
    return formatLiveCaptionsForClipboard(
      segments: _liveCaptionsStore.historyMergedSegments(),
      participantNamesByIdentity: participantNamesByIdentity,
    );
  }

  void registerLiveCaptionsTranscriptionHandlers() {
    on<UpsertLiveCaptionSegment>(_onUpsertLiveCaptionSegment);
    on<LiveCaptionsTranscriptionTick>(_onLiveCaptionsTranscriptionTick);
    on<ClearLiveCaptionsTranscriptions>(_onClearLiveCaptionsTranscriptions);
    on<LiveCaptionsTranscriptionStreamStarted>(
      _onLiveCaptionsTranscriptionStreamStarted,
    );
    on<LiveCaptionsTranscriptionStreamReadFailed>(
      _onLiveCaptionsTranscriptionStreamReadFailed,
    );
    on<LiveCaptionsTranscriptionStreamDecryptFailed>(
      _onLiveCaptionsTranscriptionStreamDecryptFailed,
    );
    on<RefreshLiveCaptionsTranscriptions>(_onRefreshLiveCaptionsTranscriptions);
  }

  /// Transcription pipeline hook when the STT agent joins (called from agent lifecycle).
  void onLiveCaptionsCaptionAgentConnectedForTranscription(
    Emitter<RoomState> emit,
  ) {
    if (!isMeetLiveCaptionsEnabled() || !state.liveCaptionsWanted || isClosed) {
      return;
    }
    ensureLiveCaptionsTranscriptionHandler();
    _scheduleLiveCaptionsReadyTimeout();
    _emitLiveCaptionsTranscriptions(emit);
  }

  /// Registers the `lk.transcription` handler on [room] if not already active.
  void ensureLiveCaptionsTranscriptionHandler({Room? room}) {
    if (!isMeetLiveCaptionsEnabled()) {
      return;
    }
    final targetRoom = room ?? state.room;
    if (_roomsWithTranscriptionConsumer.contains(targetRoom)) {
      return;
    }
    setupLiveCaptionsTranscriptionHandler(room: targetRoom);
  }

  /// Registers the singleton `lk.transcription` handler on [room].
  void setupLiveCaptionsTranscriptionHandler({Room? room}) {
    if (!isMeetLiveCaptionsEnabled()) {
      return;
    }

    final targetRoom = room ?? state.room;
    if (_roomsWithTranscriptionConsumer.contains(targetRoom)) {
      l.logger.d(
        '[LiveCaptions] transcription handler already registered for room',
      );
      return;
    }

    targetRoom.registerTextStreamHandler(
      LiveCaptionsConstants.transcriptionTopic,
      _onTranscriptionTextStream,
    );
    _roomsWithTranscriptionConsumer.add(targetRoom);
    _liveCaptionsHandlerRoom = targetRoom;
    _liveCaptionsListening = true;
    _startLiveCaptionsExpiryTimer();
    _scheduleLiveCaptionsReadyTimeout();
    _emitLiveCaptionsTranscriptions();
  }

  /// Unregisters the handler and stops timers. Safe to call multiple times.
  void teardownLiveCaptionsTranscriptionHandler({Room? room}) {
    _liveCaptionsExpiryTimer?.cancel();
    _liveCaptionsExpiryTimer = null;
    _liveCaptionsReadyTimeoutTimer?.cancel();
    _liveCaptionsReadyTimeoutTimer = null;

    final targetRoom = room ?? _liveCaptionsHandlerRoom;
    if (targetRoom != null &&
        _roomsWithTranscriptionConsumer.contains(targetRoom)) {
      try {
        targetRoom.unregisterTextStreamHandler(
          LiveCaptionsConstants.transcriptionTopic,
        );
      } catch (e) {
        l.logger.w('[LiveCaptions] unregisterTextStreamHandler failed: $e');
      }
      _roomsWithTranscriptionConsumer.remove(targetRoom);
    }

    if (room == null || room == _liveCaptionsHandlerRoom) {
      _liveCaptionsHandlerRoom = null;
      _liveCaptionsListening = false;
    }
  }

  /// Clears in-memory segments/diagnostics and resets caption bar state.
  void resetLiveCaptionsTranscriptionPipeline({bool emitUpdate = true}) {
    _liveCaptionsStore.clear();
    _liveCaptionsDiagnostics = TranscriptionDiagnostics();
    _liveCaptionsFailing = false;
    _liveCaptionsReadyTimeoutTimer?.cancel();
    _liveCaptionsReadyTimeoutTimer = null;
    if (emitUpdate && !isClosed) {
      _emitLiveCaptionsTranscriptions();
    }
  }

  void _startLiveCaptionsExpiryTimer() {
    _liveCaptionsExpiryTimer?.cancel();
    _liveCaptionsExpiryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isClosed) {
        add(const LiveCaptionsTranscriptionTick());
      }
    });
  }

  void _scheduleLiveCaptionsReadyTimeout() {
    _liveCaptionsReadyTimeoutTimer?.cancel();
    if (!_liveCaptionsListening || !_isCaptionAgentPresent()) {
      return;
    }
    _liveCaptionsReadyTimeoutTimer = Timer(
      LiveCaptionsConstants.readyTimeout,
      () {
        if (isClosed) {
          return;
        }
        if (_liveCaptionsStore.isEmpty &&
            _liveCaptionsDiagnostics.streamsReceived == 0) {
          l.logger.w(
            '[LiveCaptions] agent present but no transcription streams received '
            'within ${LiveCaptionsConstants.readyTimeout.inSeconds}s',
          );
        }
        _updateLiveCaptionsFailingFromDiagnostics();
        _emitLiveCaptionsTranscriptions();
      },
    );
  }

  void _onTranscriptionTextStream(
    TextStreamReader reader,
    String participantIdentity,
  ) {
    // Subscribe synchronously in the SDK callback. Deferring readAll() (or
    // returning before subscribing) leaves the stream open until the trailer
    // arrives; a duplicate header for the same stream id then throws
    // DataStreamErrorReason.AlreadyOpened (common when the agent sends while
    // participants are still joining).
    try {
      _subscribeTranscriptionTextStream(reader, participantIdentity);
    } catch (e, stackTrace) {
      l.logger.w(
        '[LiveCaptions] transcription handler failed before subscribe: $e',
        error: e,
        stackTrace: stackTrace,
      );
      _drainTextStream(reader);
    }
  }

  void _subscribeTranscriptionTextStream(
    TextStreamReader reader,
    String participantIdentity,
  ) {
    if (!isMeetLiveCaptionsEnabled() || isClosed || !state.liveCaptionsWanted) {
      _drainTextStream(reader);
      return;
    }

    final info = reader.info;
    final attributes = info?.attributes ?? const <String, String>{};
    final streamAttributes = TranscriptionStreamAttributes.fromMap(attributes);
    final fallbackSegmentId =
        info?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    final buffer = StringBuffer();

    reader.listen(
      (chunk) {
        if (chunk.content.isEmpty) {
          return;
        }
        try {
          buffer.write(utf8.decode(chunk.content));
        } catch (e, stackTrace) {
          l.logger.w(
            '[LiveCaptions] transcription chunk decode failed: $e',
            error: e,
            stackTrace: stackTrace,
          );
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        l.logger.w(
          '[LiveCaptions] transcription stream read failed: $error',
          error: error,
          stackTrace: stackTrace,
        );
        if (!isClosed) {
          add(const LiveCaptionsTranscriptionStreamReadFailed());
        }
      },
      onDone: () {
        if (isClosed || !state.liveCaptionsWanted) {
          return;
        }
        unawaited(
          _processTranscriptionPayload(
            payload: buffer.toString(),
            participantIdentity: participantIdentity,
            streamAttributes: streamAttributes,
            fallbackSegmentId: fallbackSegmentId,
          ),
        );
      },
      cancelOnError: true,
    );
  }

  /// Discards an incoming text stream without processing (still subscribes so
  /// LiveKit can complete the stream lifecycle).
  void _drainTextStream(TextStreamReader reader) {
    reader.listen((_) {}, onError: (_, __) {}, cancelOnError: true);
  }

  Future<void> _processTranscriptionPayload({
    required String payload,
    required String participantIdentity,
    required TranscriptionStreamAttributes streamAttributes,
    required String fallbackSegmentId,
  }) async {
    if (isClosed || !state.liveCaptionsWanted) {
      return;
    }

    if (!_isCaptionAgentTranscriptionSender(participantIdentity)) {
      return;
    }

    add(const LiveCaptionsTranscriptionStreamStarted());

    if (payload.isEmpty) {
      add(const LiveCaptionsTranscriptionStreamReadFailed());
      return;
    }

    final decrypted = await decryptTranscriptionPayload(
      appCore: _appCoreManager.appCore,
      base64Payload: payload,
    );

    if (decrypted == null || decrypted.message.isEmpty) {
      add(const LiveCaptionsTranscriptionStreamDecryptFailed());
      return;
    }

    final segment = buildCaptionSegment(
      decrypted: decrypted,
      streamAttributes: streamAttributes,
      room: state.room,
      fallbackSegmentId: fallbackSegmentId,
    );

    add(UpsertLiveCaptionSegment(segment));
  }

  bool _isCaptionAgentTranscriptionSender(String participantIdentity) {
    if (isCaptionAgentIdentity(participantIdentity)) {
      return true;
    }
    return isCaptionAgentSender(state.room, participantIdentity);
  }

  void _onUpsertLiveCaptionSegment(
    UpsertLiveCaptionSegment event,
    Emitter<RoomState> emit,
  ) {
    _liveCaptionsStore.upsert(event.segment);
    _liveCaptionsFailing = false;
    _liveCaptionsReadyTimeoutTimer?.cancel();
    _liveCaptionsReadyTimeoutTimer = null;
    _emitLiveCaptionsTranscriptions(emit);
  }

  void _onLiveCaptionsTranscriptionStreamStarted(
    LiveCaptionsTranscriptionStreamStarted event,
    Emitter<RoomState> emit,
  ) {
    _liveCaptionsDiagnostics = _liveCaptionsDiagnostics.copyWith(
      streamsReceived: _liveCaptionsDiagnostics.streamsReceived + 1,
    );
    _updateLiveCaptionsFailingFromDiagnostics();
    _emitLiveCaptionsTranscriptions(emit);
  }

  void _onLiveCaptionsTranscriptionStreamReadFailed(
    LiveCaptionsTranscriptionStreamReadFailed event,
    Emitter<RoomState> emit,
  ) {
    _liveCaptionsDiagnostics = _liveCaptionsDiagnostics.copyWith(
      streamReadFailures: _liveCaptionsDiagnostics.streamReadFailures + 1,
    );
    _updateLiveCaptionsFailingFromDiagnostics();
    _emitLiveCaptionsTranscriptions(emit);
  }

  void _onLiveCaptionsTranscriptionStreamDecryptFailed(
    LiveCaptionsTranscriptionStreamDecryptFailed event,
    Emitter<RoomState> emit,
  ) {
    _liveCaptionsDiagnostics = _liveCaptionsDiagnostics.copyWith(
      decryptFailures: _liveCaptionsDiagnostics.decryptFailures + 1,
    );
    _updateLiveCaptionsFailingFromDiagnostics();
    _emitLiveCaptionsTranscriptions(emit);
  }

  void _onLiveCaptionsTranscriptionTick(
    LiveCaptionsTranscriptionTick event,
    Emitter<RoomState> emit,
  ) {
    if (!state.liveCaptionsWanted || isClosed) {
      return;
    }
    _emitLiveCaptionsTranscriptions(emit);
  }

  void _onClearLiveCaptionsTranscriptions(
    ClearLiveCaptionsTranscriptions event,
    Emitter<RoomState> emit,
  ) {
    resetLiveCaptionsTranscriptionPipeline(emitUpdate: false);
    emit(state.copyWith(liveCaptionsTranscriptions: Transcriptions.empty));
  }

  void _onRefreshLiveCaptionsTranscriptions(
    RefreshLiveCaptionsTranscriptions event,
    Emitter<RoomState> emit,
  ) {
    emit(state.copyWith(liveCaptionsTranscriptions: event.transcriptions));
  }

  void _updateLiveCaptionsFailingFromDiagnostics() {
    final diagnostics = _liveCaptionsDiagnostics;
    if (diagnostics.streamsReceived > 0 &&
        diagnostics.decryptFailures >= diagnostics.streamsReceived &&
        _liveCaptionsStore.isEmpty) {
      _liveCaptionsFailing = true;
    }
  }

  bool _isCaptionAgentPresent() {
    return state.room.remoteParticipants.values.any(isCaptionAgent);
  }

  void _emitLiveCaptionsTranscriptions([Emitter<RoomState>? emit]) {
    if (isClosed) {
      return;
    }

    final transcriptions = _liveCaptionsStore.snapshot(
      nowMs: DateTime.now().millisecondsSinceEpoch,
      failing: _liveCaptionsFailing,
      listening: _liveCaptionsListening,
      agentPresent: _isCaptionAgentPresent(),
    );

    if (emit != null) {
      emit(state.copyWith(liveCaptionsTranscriptions: transcriptions));
      return;
    }

    add(RefreshLiveCaptionsTranscriptions(transcriptions));
  }
}
