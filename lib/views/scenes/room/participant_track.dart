import 'package:livekit_client/livekit_client.dart';

enum ParticipantTrackType {
  kUserMedia,
  kScreenShare;

  TrackSource get lkVideoSourceType {
    switch (this) {
      case ParticipantTrackType.kUserMedia:
        return TrackSource.camera;
      case ParticipantTrackType.kScreenShare:
        return TrackSource.screenShareVideo;
    }
  }

  TrackSource get lkAudioSourceType {
    switch (this) {
      case ParticipantTrackType.kUserMedia:
        return TrackSource.microphone;
      case ParticipantTrackType.kScreenShare:
        return TrackSource.screenShareAudio;
    }
  }
}

class ParticipantTrack {
  final Participant participant;
  final ParticipantTrackType type;

  const ParticipantTrack({
    required this.participant,
    this.type = ParticipantTrackType.kUserMedia,
  });
}
