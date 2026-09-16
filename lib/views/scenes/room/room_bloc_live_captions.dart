import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/helper/extension/live_caption_participant_attributes.dart';
import 'package:meet/helper/logger.dart' as l;

import 'room_bloc_feature_flags.dart';
import 'room_bloc_live_captions_transcriptions.dart';
import 'room_event.dart';
import 'room_event_livekit.dart';
import 'room_state.dart';

/// Live captions preference writes and attribute sync for the in-room UI.
mixin RoomLiveCaptionsHandlers
    on
        Bloc<RoomBlocEvent, RoomState>,
        RoomFeatureFlagsHandlers,
        RoomLiveCaptionsTranscriptionHandlers {
  void registerLiveCaptionsHandlers() {
    on<SetLiveCaptionsWanted>(_onSetLiveCaptionsWanted);
    on<SetLiveCaptionLanguage>(_onSetLiveCaptionLanguage);
    on<BridgeParticipantAttributesChanged>(
      _onBridgeParticipantAttributesChanged,
    );
    on<LiveCaptionsSummonFailedErrorConsumed>(
      _onLiveCaptionsSummonFailedErrorConsumed,
    );
  }

  void _onLiveCaptionsSummonFailedErrorConsumed(
    LiveCaptionsSummonFailedErrorConsumed event,
    Emitter<RoomState> emit,
  ) {
    emit(state.copyWith(shouldShowLiveCaptionsSummonFailedError: false));
  }

  /// Reads local participant caption attributes into [RoomState].
  void syncLiveCaptionsPreferencesFromLocal(Emitter<RoomState> emit) {
    final local = state.room.localParticipant;
    if (local == null) {
      return;
    }
    emit(
      state.copyWith(
        liveCaptionsWanted: local.wantsCaptions,
        liveCaptionLanguage: local.captionLanguage,
        liveCaptionsAttributesGeneration:
            state.liveCaptionsAttributesGeneration + 1,
      ),
    );
  }

  Future<void> _onSetLiveCaptionsWanted(
    SetLiveCaptionsWanted event,
    Emitter<RoomState> emit,
  ) async {
    if (!isMeetLiveCaptionsEnabled()) {
      return;
    }
    final local = state.room.localParticipant;
    if (local == null) {
      return;
    }

    emit(state.copyWith(isLiveCaptionsPreferenceWriteInFlight: true));
    try {
      await local.setLiveCaptionsWanted(enabled: event.enabled);
      syncLiveCaptionsPreferencesFromLocal(emit);
      if (event.enabled) {
        ensureLiveCaptionsTranscriptionHandler();
      } else {
        add(const ClearLiveCaptionsTranscriptions());
      }
      add(const EvaluateLiveCaptionsAgentLifecycle());
    } catch (e, stackTrace) {
      l.logger.e(
        '[RoomLiveCaptionsHandlers] setLiveCaptionsWanted failed: $e',
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      emit(state.copyWith(isLiveCaptionsPreferenceWriteInFlight: false));
    }
  }

  Future<void> _onSetLiveCaptionLanguage(
    SetLiveCaptionLanguage event,
    Emitter<RoomState> emit,
  ) async {
    if (!isMeetLiveCaptionsEnabled() ||
        !isMeetLiveCaptionsLanguageSelectorEnabled()) {
      return;
    }
    final local = state.room.localParticipant;
    if (local == null) {
      return;
    }

    emit(state.copyWith(isLiveCaptionsPreferenceWriteInFlight: true));
    try {
      await local.setLiveCaptionLanguage(event.language);
      syncLiveCaptionsPreferencesFromLocal(emit);
    } catch (e, stackTrace) {
      l.logger.e(
        '[RoomLiveCaptionsHandlers] setLiveCaptionLanguage failed: $e',
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      emit(state.copyWith(isLiveCaptionsPreferenceWriteInFlight: false));
    }
  }

  void _onBridgeParticipantAttributesChanged(
    BridgeParticipantAttributesChanged event,
    Emitter<RoomState> emit,
  ) {
    if (!isMeetLiveCaptionsEnabled()) {
      return;
    }

    final local = state.room.localParticipant;
    final changedParticipant = event.event.participant;
    final isLocalChange = local != null && changedParticipant.sid == local.sid;

    if (isLocalChange) {
      final wanted = local.wantsCaptions;
      emit(
        state.copyWith(
          liveCaptionsWanted: wanted,
          liveCaptionLanguage: local.captionLanguage,
          liveCaptionsAttributesGeneration:
              state.liveCaptionsAttributesGeneration + 1,
        ),
      );
      if (!wanted) {
        add(const ClearLiveCaptionsTranscriptions());
      }
      add(const EvaluateLiveCaptionsAgentLifecycle());
      return;
    }

    emit(
      state.copyWith(
        liveCaptionsAttributesGeneration:
            state.liveCaptionsAttributesGeneration + 1,
      ),
    );
    add(const EvaluateLiveCaptionsAgentLifecycle());
  }
}
