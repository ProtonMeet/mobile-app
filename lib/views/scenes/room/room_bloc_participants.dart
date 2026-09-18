// room_participants_handlers.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/models/live_captions/live_caption_agent.dart';
import 'package:meet/rust/proton_meet/models/meet_participant.dart';

import 'participant_detail.dart';
import 'room_event.dart';
import 'room_event_livekit.dart';
import 'room_state.dart';

mixin RoomParticipantsHandlers on Bloc<RoomBlocEvent, RoomState> {
  // Threshold for determining large vs small meetings
  // Shared with RoomBloc for consistency
  final int largeMeetingThreshold = 50;
  static const int _maxJoinLeaveHistory = 50;
  static const Duration _livekitActiveUuidRefreshInterval = Duration(
    seconds: 10,
  );

  Timer? _livekitActiveUuidTimer;

  void registerParticipantHandlers() {
    /// livekit events
    on<BridgeParticipantConnected>(_onParticipantConnected);
    on<BridgeParticipantDisconnected>(_onParticipantDisconnected);
    on<BackgroundRefreshFrbParticipants>(_onBackgroundRefreshFrbParticipants);
  }

  Future<void> _onBackgroundRefreshFrbParticipants(
    BackgroundRefreshFrbParticipants event,
    Emitter<RoomState> emit,
  ) async {
    try {
      final updated = await loadFrbParticipants();
      emit(state.copyWith(frbParticipantsMap: updated));
      add(SortParticipants());
    } catch (e, stackTrace) {
      l.logger.e(
        '[RoomParticipantsHandlers] Background FRB participant load failed: $e',
        error: e,
        stackTrace: stackTrace,
      );
      add(const RetryLoadParticipants());
    }
  }

  /// Handles the event when a participant connects to the room.
  ///
  /// This method loads the updated participant list from the FRB (Flutter Rust Bridge)
  /// and adds the participant to the joined participants list if not already present.
  /// Also applies speaker mute state to the new participant's audio tracks if speaker is muted.
  ///
  /// Parameters:
  /// - [event]: The bridge event containing participant connection information
  /// - [emit]: State emitter for updating the room state
  Future<void> _onParticipantConnected(
    BridgeParticipantConnected event,
    Emitter<RoomState> emit,
  ) async {
    try {
      final updated = await loadFrbParticipants();
      emit(state.copyWith(frbParticipantsMap: updated));
    } catch (e, stackTrace) {
      l.logger.e(
        '[RoomParticipantsHandlers] Error loading FRB participants: $e',
        error: e,
        stackTrace: stackTrace,
      );
      add(RetryLoadParticipants());
    }

    final joinedParticipants = List<ParticipantDetail>.of(
      state.joinedParticipants,
    );
    final participantIdentity = event.event.participant.identity;
    if (!joinedParticipants.any((p) => p.uuid == participantIdentity)) {
      joinedParticipants.add(
        ParticipantDetail(
          name: getParticipantDisplayName(event.event.participant),
          uuid: participantIdentity,
        ),
      );
      if (joinedParticipants.length > _maxJoinLeaveHistory) {
        joinedParticipants.removeRange(
          0,
          joinedParticipants.length - _maxJoinLeaveHistory,
        );
      }
      emit(state.copyWith(joinedParticipants: joinedParticipants.toList()));
    }

    // Apply speaker mute state to new participant's audio tracks
    final participant = event.event.participant;
    final isSpeakerMuted = state.isSpeakerMuted ?? false;
    if (isSpeakerMuted) {
      // Apply mute state to all existing audio tracks
      for (final pub in participant.audioTrackPublications) {
        final track = pub.track;
        if (track is RemoteAudioTrack) {
          try {
            await track.disable();
          } catch (e) {
            // Log error but don't fail the connection
          }
        }
      }
    }
    _updateLivekitActiveUuids();
    add(SortParticipants());

    if (state.isRoomInitialized) {
      if (isCaptionAgent(participant)) {
        add(const LiveCaptionsCaptionAgentConnected());
      }
      add(const EvaluateLiveCaptionsAgentLifecycle());
    }
  }

  /// Handles the event when a participant disconnects from the room.
  ///
  /// This method adds the disconnected participant to the left participants list
  /// if not already present, allowing the UI to track and display who has left.
  ///
  /// Parameters:
  /// - [event]: The bridge event containing participant disconnection information
  /// - [emit]: State emitter for updating the room state
  Future<void> _onParticipantDisconnected(
    BridgeParticipantDisconnected event,
    Emitter<RoomState> emit,
  ) async {
    final leftParticipants = List<ParticipantDetail>.of(state.leftParticipants);
    final participantIdentity = event.event.participant.identity;
    if (!leftParticipants.any((p) => p.uuid == participantIdentity)) {
      leftParticipants.add(
        ParticipantDetail(
          name: getParticipantDisplayName(event.event.participant),
          uuid: participantIdentity,
        ),
      );
      if (leftParticipants.length > _maxJoinLeaveHistory) {
        leftParticipants.removeRange(
          0,
          leftParticipants.length - _maxJoinLeaveHistory,
        );
      }
      emit(state.copyWith(leftParticipants: leftParticipants.toList()));
    }
    _updateLivekitActiveUuids();

    // Auto-clear stale recording state when a recorder drops out without
    // sending us a Stopped envelope, otherwise the banner could get stuck.
    if (state.participantsRecording.contains(participantIdentity)) {
      add(ParticipantRecordingStopped(identity: participantIdentity));
    }

    final disconnectedParticipant = event.event.participant;
    if (state.isRoomInitialized) {
      if (isCaptionAgent(disconnectedParticipant)) {
        add(const LiveCaptionsCaptionAgentDisconnected());
      } else {
        add(const EvaluateLiveCaptionsAgentLifecycle());
      }
    }
  }

  void startLivekitActiveUuidRefresh() {
    stopLivekitActiveUuidRefresh();
    _updateLivekitActiveUuids();
    _livekitActiveUuidTimer = Timer.periodic(
      _livekitActiveUuidRefreshInterval,
      (timer) {
        if (isClosed) {
          timer.cancel();
          return;
        }
        _updateLivekitActiveUuids();
      },
    );
  }

  void stopLivekitActiveUuidRefresh() {
    _livekitActiveUuidTimer?.cancel();
    _livekitActiveUuidTimer = null;
  }

  /// Updates the list of active LiveKit participant UUIDs in AppCore.
  ///
  /// Collects all active participant identities (local and remote) from the room
  /// and updates the AppCore manager with the current list of active UUIDs.
  void _updateLivekitActiveUuids() {
    final activeUuids = <String>[];

    if (state.room.localParticipant != null) {
      activeUuids.add(state.room.localParticipant!.identity);
    }

    for (final participant in state.room.remoteParticipants.values) {
      activeUuids.add(participant.identity);
    }

    final appCoreManager = ManagerFactory().get<AppCoreManager>();
    appCoreManager.appCore.setLivekitActiveUuids(
      activeUuids: activeUuids,
      isAgentInLivekit:
          false, // TODO: check if agent is in livekit in live caption PR
    );
  }

  /// Retrieves the display name for a participant.
  ///
  /// Returns the participant's display name from the FRB participants map,
  /// or falls back to a localized "Loading..." string if no display name is found.
  /// If `isScreenShare` is true, appends a screen share indicator to the name.
  ///
  /// Parameters:
  /// - `participant`: The LiveKit participant to get the display name for
  /// - `context`: Optional BuildContext for localization. If not provided,
  ///   falls back to a hardcoded "Loading ..." string.
  /// - `isScreenShare`: Whether this is for a screen share track. Defaults to false.
  ///
  /// Returns:
  /// The participant's display name or localized fallback, optionally with screen share indicator
  String getParticipantDisplayName(
    Participant participant, {
    BuildContext? context,
    bool isRemoteScreenShare = false,
    bool isLocalScreenShare = false,
  }) {
    final displayName =
        state.frbParticipantsMap[participant.identity]?.displayName ??
        context?.local.loading ??
        'Loading ...';

    if (isRemoteScreenShare) {
      return context?.local.remote_user_is_presenting(displayName) ??
          '$displayName is presenting';
    }
    if (isLocalScreenShare) {
      return context?.local.user_is_presenting(displayName) ??
          '$displayName (you) is presenting';
    }

    return displayName;
  }

  bool isParticipantExists(Participant participant) {
    return state.frbParticipantsMap.containsKey(participant.identity);
  }

  /// Loads participants from the backend via FRB (Flutter Rust Bridge).
  ///
  /// Fetches the latest participant list from the app core manager and merges
  /// it with the existing participants map. New participants are added and
  /// existing participants are updated with fresh data from the API.
  ///
  /// Returns:
  /// A map of participant UUIDs to [MeetParticipant] objects
  /// Resolves a participant display name by UUID via meet-server `getParticipants`
  /// (decrypted in Rust using the cached meeting session key).
  ///
  /// Waiting-room join requests only carry `participant_uid`; names come from this API.
  Future<({Map<String, MeetParticipant> participants, String? displayName})>
  resolveParticipantDisplayNameByUuid(String participantUuid) async {
    try {
      final updated = await loadFrbParticipants();
      final displayName = updated[participantUuid]?.displayName?.trim();
      return (
        participants: updated,
        displayName: displayName != null && displayName.isNotEmpty
            ? displayName
            : null,
      );
    } catch (e, stackTrace) {
      l.logger.w(
        '[RoomParticipantsHandlers] resolveParticipantDisplayNameByUuid failed: $e',
        stackTrace: stackTrace,
      );
      final cached = state.frbParticipantsMap[participantUuid]?.displayName
          ?.trim();
      return (
        participants: state.frbParticipantsMap,
        displayName: cached != null && cached.isNotEmpty ? cached : null,
      );
    }
  }

  Future<Map<String, MeetParticipant>> loadFrbParticipants() async {
    final meetInfo = state.meetInfo;
    final appCoreManager = ManagerFactory().get<AppCoreManager>();
    final frbParticipants = await appCoreManager.appCore.getParticipants(
      meetLinkName: meetInfo.meetLinkName,
    );
    final updated = Map<String, MeetParticipant>.of(state.frbParticipantsMap);
    // Update existing participants and add new ones (like WebApp does)
    for (final p in frbParticipants) {
      updated[p.participantUuid] = p;
    }

    return updated;
  }

  Future<Map<String, MeetParticipant>> buildLocalFrbParticipant() async {
    final updated = Map<String, MeetParticipant>.of(state.frbParticipantsMap);
    final localParticipant = state.room.localParticipant;
    if (localParticipant != null) {
      final existing = updated[localParticipant.identity];
      final isHostHint = state.localHostHint;
      updated[localParticipant.identity] = MeetParticipant(
        participantUuid: localParticipant.identity,
        displayName: state.displayName,
        encryptedDisplayName: existing?.encryptedDisplayName,
        canSubscribe: existing?.canSubscribe,
        canPublish: existing?.canPublish,
        canPublishData: existing?.canPublishData,
        isAdmin: isHostHint ? 1 : existing?.isAdmin,
        isHost: isHostHint ? 1 : existing?.isHost,
      );
    }
    return updated;
  }
}
