import 'package:livekit_client/livekit_client.dart';
import 'package:meet/views/scenes/room/participant/participant_info.dart';
import 'package:meet/views/scenes/room/room_bloc_tracks.dart'
    show RoomTracksHandlers;
import 'package:meet/views/scenes/room/room_state.dart';

/// Sorts participants by dominant-speaker priority (not grid page / not capped).
///
/// Rules (same as [RoomTracksHandlers.sortUserMediaTracksBySpoken]):
/// 1) Raised hand first
/// 2) [lastSpokeAt] DESC (if both spoke within 10s, stable sort by identity)
/// 3) Camera on before off
/// 4) [joinedAt] ASC
/// 5) Identity tiebreaker
void sortParticipantsByActiveSpeakerPriority(
  List<ParticipantInfo> tracks,
  Map<String, bool> raisedHandsByIdentity,
) {
  const recentWindowMs = 10000; // 10 seconds
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  final raisedMap = raisedHandsByIdentity;

  // Cache sort keys once before sorting.
  // This avoids repeatedly reading Participant getters from the comparator.
  final decorated = List.generate(tracks.length, (i) {
    final t = tracks[i];
    final p = t.participant;
    final lastSpokeAt = p.lastSpokeAt;
    final lastSpokeMs = lastSpokeAt?.millisecondsSinceEpoch ?? 0;
    return (
      info: t,
      identity: p.identity,
      raised: raisedMap[p.identity] == true,
      lastSpokeMs: lastSpokeMs,
      isRecent: lastSpokeAt != null && (nowMs - lastSpokeMs) <= recentWindowMs,
      cameraEnabled: p.isCameraEnabled(),
      joinedAtMs: p.joinedAt.millisecondsSinceEpoch,
    );
  });

  // Sort the decorated records — comparator never touches the
  // underlying [Participant] getters.
  decorated.sort((a, b) {
    // Raised hand gets the highest priority.
    if (a.raised != b.raised) return a.raised ? -1 : 1;

    // If both spoke recently, keep a stable order by identity to
    // prevent UI flicker.
    if (a.isRecent && b.isRecent) {
      final idCmp = a.identity.compareTo(b.identity);
      if (idCmp != 0) return idCmp;
      // fall through to next criteria if identities are equal
    } else if (a.lastSpokeMs != b.lastSpokeMs) {
      // Otherwise, order by lastSpokeAt DESC (0 means "never" and
      // naturally sinks).
      return b.lastSpokeMs.compareTo(a.lastSpokeMs);
    }

    // Camera ON before OFF.
    if (a.cameraEnabled != b.cameraEnabled) {
      return a.cameraEnabled ? -1 : 1;
    }

    // Earlier joiners first.
    final joinCmp = a.joinedAtMs.compareTo(b.joinedAtMs);
    if (joinCmp != 0) return joinCmp;

    // Final deterministic tiebreaker: identity.
    return a.identity.compareTo(b.identity);
  });

  // Undecorate in-place: write back the [ParticipantInfo]s in the
  // newly sorted order, preserving the in-place contract of [List.sort].
  for (var i = 0; i < decorated.length; i++) {
    tracks[i] = decorated[i].info;
  }
}

bool isUsablePipDisplayName(String name, String participantIdentity) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed == participantIdentity) return false;
  if (trimmed.toLowerCase().startsWith('loading')) return false;
  return true;
}

/// Human-readable name for PiP overlay — never prefers raw LiveKit [Participant.identity].
String pipDisplayNameFor(Participant participant, RoomState state) {
  for (final list in [
    state.participantTracks,
    state.speakerTracks,
    state.screenSharingTracks,
  ]) {
    for (final info in list) {
      if (info.participant.identity != participant.identity) continue;
      if (isUsablePipDisplayName(info.displayName, participant.identity)) {
        return info.displayName.trim();
      }
    }
  }

  final fromFrb =
      state.frbParticipantsMap[participant.identity]?.displayName?.trim() ?? '';
  if (isUsablePipDisplayName(fromFrb, participant.identity)) {
    return fromFrb;
  }

  final liveKitName = participant.name.trim();
  if (isUsablePipDisplayName(liveKitName, participant.identity)) {
    return liveKitName;
  }

  if (fromFrb.isNotEmpty) return fromFrb;
  if (liveKitName.isNotEmpty) return liveKitName;
  return 'Guest';
}

ParticipantInfo participantInfoFrom(Participant participant, RoomState state) {
  return ParticipantInfo(
    participant: participant,
    displayName: pipDisplayNameFor(participant, state),
  );
}

/// Full-room active speaker order: all remotes, local excluded, sorted by [lastSpokeAt].
///
/// Unlike [RoomState.speakerTracks], this is not limited to four recent speakers
/// and does not depend on grid pagination or [participantTracks] page order.
List<ParticipantInfo> activeSpeakerOrderFromRoom(
  RoomState state, {
  bool excludeLocalParticipant = true,
}) {
  final room = state.room;
  final localIdentity = room.localParticipant?.identity;
  final candidates = <ParticipantInfo>[];

  for (final participant in room.remoteParticipants.values) {
    if (excludeLocalParticipant && participant.identity == localIdentity) {
      continue;
    }
    candidates.add(participantInfoFrom(participant, state));
  }

  sortParticipantsByActiveSpeakerPriority(
    candidates,
    state.raisedHandsByIdentity,
  );
  return candidates;
}

/// Dominant remote active speaker for PiP / spotlight (excludes self).
ParticipantInfo? dominantActiveSpeakerFromRoom(RoomState state) {
  final order = activeSpeakerOrderFromRoom(state);
  if (order.isEmpty) return null;

  ParticipantInfo? speakingNow;
  for (final info in order) {
    if (!info.participant.isSpeaking) continue;
    final spokeAt = info.participant.lastSpokeAt?.millisecondsSinceEpoch ?? 0;
    final currentSpokeAt =
        speakingNow?.participant.lastSpokeAt?.millisecondsSinceEpoch ?? 0;
    if (speakingNow == null || spokeAt >= currentSpokeAt) {
      speakingNow = info;
    }
  }
  if (speakingNow != null) return speakingNow;

  return order.first;
}
