import 'package:livekit_client/livekit_client.dart';
import 'package:meet/managers/pip/ios_pip_avatar_palette.dart';
import 'package:meet/managers/pip/ios_pip_track_ids.dart'
    show
        IosPipTrackIds,
        participantCameraVideoActiveForPip,
        trackIdsFromVideoTrack,
        videoTrackForSource;
import 'package:meet/views/scenes/room/active_speaker_order.dart'
    show
        activeSpeakerOrderFromRoom,
        dominantActiveSpeakerFromRoom,
        isUsablePipDisplayName,
        pipDisplayNameFor;
import 'package:meet/views/scenes/room/participant/participant_info.dart';
import 'package:meet/views/scenes/room/room_state.dart';
import 'package:meet/views/scenes/utils.dart';

/// Participant metadata + optional WebRTC ids for iOS system PiP.
class IosPipPresentation {
  const IosPipPresentation({
    required this.participantIdentity,
    required this.displayName,
    required this.initials,
    required this.colorIndex,
    required this.hasVideo,
    this.trackIds,
  });

  final String participantIdentity;
  final String displayName;
  final String initials;
  final int colorIndex;
  final bool hasVideo;
  final IosPipTrackIds? trackIds;

  int get backgroundColorArgb => IosPipAvatarPalette.backgroundArgb(colorIndex);
  int get profileTextColorArgb =>
      IosPipAvatarPalette.profileTextArgb(colorIndex);

  Map<String, dynamic> toMethodChannelArgs() {
    final ids = trackIds;
    return {
      'participantIdentity': participantIdentity,
      'displayName': displayName,
      'initials': initials,
      'backgroundColor': backgroundColorArgb,
      'profileTextColor': profileTextColorArgb,
      'hasVideo': hasVideo,
      'remoteStreamId': ids?.remoteStreamId ?? '',
      'peerConnectionId': ids?.peerConnectionId ?? '',
      'videoTrackId': ids?.videoTrackId ?? '',
    };
  }

  @override
  bool operator ==(Object other) {
    return other is IosPipPresentation &&
        participantIdentity == other.participantIdentity &&
        displayName == other.displayName &&
        initials == other.initials &&
        colorIndex == other.colorIndex &&
        hasVideo == other.hasVideo &&
        trackIds == other.trackIds;
  }

  @override
  int get hashCode => Object.hash(
    participantIdentity,
    displayName,
    initials,
    colorIndex,
    hasVideo,
    trackIds,
  );
}

/// Zoom-style PiP: screen share → active speaker → speaker list → local (solo).
IosPipPresentation? resolveIosPipPresentationFromState(RoomState state) {
  if (state.isRemoteScreenSharing || state.isLocalScreenSharing) {
    for (final info in state.screenSharingTracks) {
      final presentation = _presentationFromParticipantInfo(
        state,
        info,
        preferScreenShare: true,
      );
      if (presentation != null) return presentation;
    }
  }

  final dominantSpeaker = dominantActiveSpeakerFromRoom(state);
  if (dominantSpeaker != null) {
    final presentation = _presentationFromParticipantInfo(
      state,
      dominantSpeaker,
    );
    if (presentation != null) return presentation;
  }

  for (final info in activeSpeakerOrderFromRoom(state)) {
    final presentation = _presentationFromParticipantInfo(state, info);
    if (presentation != null) return presentation;
  }

  final local = state.room.localParticipant;
  if (local != null) {
    return _presentationFromParticipant(
      state,
      local,
      local.name.isNotEmpty ? local.name : local.identity,
    );
  }

  return null;
}

IosPipPresentation? resolveIosPipPresentation(Room room, RoomState state) {
  for (final participant in room.remoteParticipants.values) {
    final presentation = _presentationFromParticipant(
      state,
      participant,
      participant.name.isNotEmpty ? participant.name : participant.identity,
    );
    if (presentation != null) return presentation;
  }

  final local = room.localParticipant;
  if (local != null) {
    return _presentationFromParticipant(
      state,
      local,
      local.name.isNotEmpty ? local.name : local.identity,
    );
  }

  return null;
}

IosPipPresentation? _presentationFromParticipantInfo(
  RoomState state,
  ParticipantInfo info, {
  bool preferScreenShare = false,
}) {
  final preferScreen =
      preferScreenShare || info.type == ParticipantTrackType.kScreenShare;
  final displayName =
      preferScreen &&
          isUsablePipDisplayName(info.displayName, info.participant.identity)
      ? info.displayName.trim()
      : pipDisplayNameFor(info.participant, state);
  return _presentationFromParticipant(
    state,
    info.participant,
    displayName,
    preferScreenShare: preferScreen,
  );
}

IosPipPresentation? _presentationFromParticipant(
  RoomState state,
  Participant participant,
  String displayName, {
  bool preferScreenShare = false,
}) {
  final label = isUsablePipDisplayName(displayName, participant.identity)
      ? displayName.trim()
      : pipDisplayNameFor(participant, state);

  VideoTrack? track;

  if (preferScreenShare) {
    track = videoTrackForSource(participant, TrackSource.screenShareVideo);
    final trackIds = trackIdsFromVideoTrack(track);
    return IosPipPresentation(
      participantIdentity: participant.identity,
      displayName: label,
      initials: getInitials(label),
      colorIndex: _colorIndexForParticipant(state, participant.identity),
      hasVideo: trackIds != null,
      trackIds: trackIds,
    );
  }

  track = videoTrackForSource(participant, TrackSource.camera);
  final cameraVideoOn = participantCameraVideoActiveForPip(participant);
  final trackIds = trackIdsFromVideoTrack(track);

  return IosPipPresentation(
    participantIdentity: participant.identity,
    displayName: label,
    initials: getInitials(label),
    colorIndex: _colorIndexForParticipant(state, participant.identity),
    hasVideo: cameraVideoOn,
    trackIds: trackIds,
  );
}

int _colorIndexForParticipant(RoomState state, String identity) {
  for (final list in [
    state.speakerTracks,
    state.participantTracks,
    state.screenSharingTracks,
  ]) {
    final index = list.indexWhere(
      (info) => info.participant.identity == identity,
    );
    if (index != -1) return index;
  }
  return identity.hashCode.abs() % 6;
}
