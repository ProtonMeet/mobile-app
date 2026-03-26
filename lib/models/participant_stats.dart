import 'package:livekit_client/livekit_client.dart';

class VideoStats {
  final int bitrate;
  final int packetsLost;
  final int packetsReceived;
  final double frameRate;
  final int frameWidth;
  final int frameHeight;
  final String encoder;
  final String codec;
  final int payload;
  final String qualityLimitationReason;
  final int qualityLimitationResolutionChanges;
  final double roundTripTime;

  VideoStats({
    this.bitrate = 0,
    this.packetsLost = 0,
    this.packetsReceived = 0,
    this.frameRate = 0,
    this.frameWidth = 0,
    this.frameHeight = 0,
    this.encoder = '',
    this.codec = '',
    this.payload = 0,
    this.qualityLimitationReason = '',
    this.qualityLimitationResolutionChanges = 0,
    this.roundTripTime = 0,
  });

  Map<String, dynamic> toJson() => {
    'bitrate': bitrate,
    'packetsLost': packetsLost,
    'packetsReceived': packetsReceived,
    'frameRate': frameRate,
    'frameWidth': frameWidth,
    'frameHeight': frameHeight,
    'encoder': encoder,
    'codec': codec,
    'payload': payload,
    'qualityLimitationReason': qualityLimitationReason,
    'qualityLimitationResolutionChanges': qualityLimitationResolutionChanges,
    'roundTripTime': roundTripTime,
  };

  factory VideoStats.fromJson(Map<String, dynamic> json) => VideoStats(
    bitrate: json['bitrate'] ?? 0,
    packetsLost: json['packetsLost'] ?? 0,
    packetsReceived: json['packetsReceived'] ?? 0,
    frameRate: json['frameRate']?.toDouble() ?? 0,
    frameWidth: json['frameWidth'] ?? 0,
    frameHeight: json['frameHeight'] ?? 0,
    encoder: json['encoder'] ?? '',
    codec: json['codec'] ?? '',
    payload: json['payload'] ?? 0,
    qualityLimitationReason: json['qualityLimitationReason'] ?? '',
    qualityLimitationResolutionChanges:
        json['qualityLimitationResolutionChanges'] ?? 0,
    roundTripTime: json['roundTripTime']?.toDouble() ?? 0,
  );
}

class AudioStats {
  final int bitrate;
  final int packetsLost;
  final int packetsSent;
  final int packetsReceived;
  final String codec;
  final int payload;
  final double jitter;
  final int concealedSamples;
  final int concealmentEvents;
  final double roundTripTime;

  AudioStats({
    this.bitrate = 0,
    this.packetsLost = 0,
    this.packetsSent = 0,
    this.packetsReceived = 0,
    this.codec = '',
    this.payload = 0,
    this.jitter = 0,
    this.concealedSamples = 0,
    this.concealmentEvents = 0,
    this.roundTripTime = 0,
  });

  Map<String, dynamic> toJson() => {
    'bitrate': bitrate,
    'packetsLost': packetsLost,
    'packetsSent': packetsSent,
    'packetsReceived': packetsReceived,
    'codec': codec,
    'payload': payload,
    'jitter': jitter,
    'concealedSamples': concealedSamples,
    'concealmentEvents': concealmentEvents,
    'roundTripTime': roundTripTime,
  };

  factory AudioStats.fromJson(Map<String, dynamic> json) => AudioStats(
    bitrate: json['bitrate'] ?? 0,
    packetsLost: json['packetsLost'] ?? 0,
    packetsSent: json['packetsSent'] ?? 0,
    packetsReceived: json['packetsReceived'] ?? 0,
    codec: json['codec'] ?? '',
    payload: json['payload'] ?? 0,
    jitter: json['jitter']?.toDouble() ?? 0,
    concealedSamples: json['concealedSamples'] ?? 0,
    concealmentEvents: json['concealmentEvents'] ?? 0,
    roundTripTime: json['roundTripTime']?.toDouble() ?? 0,
  );
}

class ConnectionStats {
  final String connectionQuality;
  final bool isPublishing;
  final String metadata;
  final String publisherConnectionState;
  final String publisherIceState;
  final int subscribedVideoTracks;
  final int subscribedAudioTracks;

  ConnectionStats({
    this.connectionQuality = '',
    this.isPublishing = false,
    this.metadata = '',
    this.publisherConnectionState = '',
    this.publisherIceState = '',
    this.subscribedVideoTracks = 0,
    this.subscribedAudioTracks = 0,
  });

  Map<String, dynamic> toJson() => {
    'connectionQuality': connectionQuality,
    'isPublishing': isPublishing,
    'metadata': metadata,
    'publisherConnectionState': publisherConnectionState,
    'publisherIceState': publisherIceState,
    'subscribedVideoTracks': subscribedVideoTracks,
    'subscribedAudioTracks': subscribedAudioTracks,
  };

  factory ConnectionStats.fromJson(Map<String, dynamic> json) =>
      ConnectionStats(
        connectionQuality: json['connectionQuality'] ?? '',
        isPublishing: json['isPublishing'] ?? false,
        metadata: json['metadata'] ?? '',
        publisherConnectionState: json['publisherConnectionState'] ?? '',
        publisherIceState: json['publisherIceState'] ?? '',
        subscribedVideoTracks: json['subscribedVideoTracks'] ?? 0,
        subscribedAudioTracks: json['subscribedAudioTracks'] ?? 0,
      );
}

class ParticipantStats {
  final String participantId;
  final String name;
  final bool isLocal;
  final Map<int, VideoStats> videoStats;
  final Map<int, AudioStats> audioStats;
  final Map<int, ConnectionStats> connectionStats;

  ParticipantStats({
    required this.participantId,
    required this.name,
    required this.isLocal,
    required this.videoStats,
    required this.audioStats,
    required this.connectionStats,
  });

  factory ParticipantStats.fromParticipant(Participant participant) {
    final isLocal = participant is LocalParticipant;
    return ParticipantStats(
      participantId: participant.identity,
      name: participant.name,
      isLocal: isLocal,
      videoStats: {0: VideoStats()},
      audioStats: {0: AudioStats()},
      connectionStats: {
        0: ConnectionStats(
          connectionQuality: participant.connectionQuality.toString(),
          isPublishing: isLocal
              ? (participant).trackPublications.isNotEmpty
              : false,
          metadata: participant.metadata ?? '',
        ),
      },
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'participantId': participantId,
      'name': name,
      'isLocal': isLocal,
      'videoStats': videoStats.map(
        (key, value) => MapEntry(key.toString(), value.toJson()),
      ),
      'audioStats': audioStats.map(
        (key, value) => MapEntry(key.toString(), value.toJson()),
      ),
      'connectionStats': connectionStats.map(
        (key, value) => MapEntry(key.toString(), value.toJson()),
      ),
    };
  }
}
