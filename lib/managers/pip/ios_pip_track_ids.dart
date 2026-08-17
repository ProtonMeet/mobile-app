import 'package:livekit_client/livekit_client.dart';

/// IDs passed to iOS native PiP (`FlutterWebRTCPlugin` track lookup).
class IosPipTrackIds {
  const IosPipTrackIds({
    required this.peerConnectionId,
    required this.remoteStreamId,
    required this.videoTrackId,
  });

  final String peerConnectionId;
  final String remoteStreamId;

  /// Native WebRTC `RTCMediaStreamTrack.trackId` — required so PiP attaches to the same
  /// decoded track as Flutter (avoid wrong `videoTracks.first` → frozen frame).
  final String videoTrackId;

  @override
  bool operator ==(Object other) {
    return other is IosPipTrackIds &&
        peerConnectionId == other.peerConnectionId &&
        remoteStreamId == other.remoteStreamId &&
        videoTrackId == other.videoTrackId;
  }

  @override
  int get hashCode =>
      Object.hash(peerConnectionId, remoteStreamId, videoTrackId);
}

/// Resolves a camera, screen-share, or local `VideoTrack` media stream for PiP on iOS.
IosPipTrackIds? resolveIosPipTrackIds(Room room) {
  VideoTrack? videoForParticipant(Participant participant) {
    return videoTrackForSource(participant, TrackSource.camera) ??
        videoTrackForSource(participant, TrackSource.screenShareVideo);
  }

  for (final participant in room.remoteParticipants.values) {
    final ids = trackIdsFromVideoTrack(videoForParticipant(participant));
    if (ids != null) return ids;
  }

  final local = room.localParticipant;
  if (local != null) {
    final ids = trackIdsFromVideoTrack(videoForParticipant(local));
    if (ids != null) return ids;
  }

  return null;
}

VideoTrack? videoTrackForSource(Participant participant, TrackSource source) {
  for (final pub in participant.videoTrackPublications) {
    if (pub.source != source) continue;
    final t = pub.track;
    if (t is VideoTrack && !pub.muted) return t;
  }
  return null;
}

/// Camera is on for PiP (even if WebRTC track is not attachable yet).
bool participantCameraVideoActiveForPip(Participant participant) {
  for (final pub in participant.videoTrackPublications) {
    if (pub.source != TrackSource.camera) continue;
    if (pub.muted) continue;
    if (pub.track is VideoTrack) return true;
  }
  return participant.isCameraEnabled() &&
      participant.videoTrackPublications.any(
        (pub) => pub.source == TrackSource.camera && !pub.muted,
      );
}

IosPipTrackIds? trackIdsFromVideoTrack(VideoTrack? track) {
  if (track == null) return null;
  final ms = track.mediaStream;
  final peer = ms.ownerTag;
  final sid = ms.id;
  final vid = track.mediaStreamTrack.id;
  if (peer.isEmpty || sid.isEmpty || vid == null || vid.isEmpty) return null;
  return IosPipTrackIds(
    peerConnectionId: peer,
    remoteStreamId: sid,
    videoTrackId: vid,
  );
}
