// ignore_for_file: invalid_use_of_internal_member

import 'dart:convert';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/models/participant_stats.dart';

class SystemLog {
  int timestamp;
  String log;

  SystemLog({required this.timestamp, required this.log});

  Map<String, dynamic> toJson() {
    return {'timestamp': timestamp, 'log': log};
  }
}

class ParticipantStatLogger {
  static final ParticipantStatLogger _instance =
      ParticipantStatLogger._internal();

  factory ParticipantStatLogger() => _instance;

  ParticipantStatLogger._internal();

  // Store system logs
  final List<SystemLog> systemLogs = [];

  // Store statistics for all participants
  final Map<String, ParticipantStats> _statsHistory = {};

  // Store listeners for all participants
  final Map<String, List<EventsListener>> _participantListeners = {};

  // Store connection listeners for all participants
  final Map<String, EventsListener<ParticipantEvent>> _connectionListeners = {};

  // Add participant to logging system, ignore if already exists
  void addParticipant(Participant participant) {
    final participantId = participant.identity;
    if (_participantListeners.containsKey(participantId)) {
      return; // Listener already exists, no need to add again
    }

    _participantListeners[participantId] = [];
    _statsHistory[participantId] = ParticipantStats.fromParticipant(
      participant,
    );

    // Setup connection listener
    _setupConnectionListener(participant);

    // Setup listeners for all existing tracks
    for (var track in [
      ...participant.videoTrackPublications,
      ...participant.audioTrackPublications,
    ]) {
      if (track.track != null) {
        _setupTrackListener(participant, track.track!);
      }
    }

    // Listen for participant changes
    participant.addListener(() {
      _onParticipantChanged(participant);
    });
  }

  void _setupConnectionListener(Participant participant) {
    final participantId = participant.identity;
    final listener = participant.createListener();
    _connectionListeners[participantId] = listener;

    listener.on<ParticipantEvent>((event) {
      _updateConnectionInfo(participant);
    });
  }

  void _setupTrackListener(Participant participant, Track track) {
    final participantId = participant.identity;
    final listener = track.createListener();
    _participantListeners[participantId]?.add(listener);

    if (track is LocalVideoTrack) {
      listener.on<VideoSenderStatsEvent>((event) {
        _logVideoSenderStats(participantId, event);
      });
    } else if (track is RemoteVideoTrack) {
      listener.on<VideoReceiverStatsEvent>((event) {
        _logVideoReceiverStats(participantId, event);
      });
    } else if (track is LocalAudioTrack) {
      listener.on<AudioSenderStatsEvent>((event) {
        _logAudioSenderStats(participantId, event);
      });
    } else if (track is RemoteAudioTrack) {
      listener.on<AudioReceiverStatsEvent>((event) {
        _logAudioReceiverStats(participantId, event);
      });
    }
  }

  void _onParticipantChanged(Participant participant) {
    final participantId = participant.identity;

    // Clean up old listeners
    _participantListeners[participantId]?.forEach((listener) {
      listener.dispose();
    });
    _participantListeners[participantId]?.clear();

    // Setup listeners for new tracks
    for (var track in [
      ...participant.videoTrackPublications,
      ...participant.audioTrackPublications,
    ]) {
      if (track.track != null) {
        _setupTrackListener(participant, track.track!);
      }
    }

    _updateConnectionInfo(participant);
  }

  void _updateConnectionInfo(Participant participant) {
    final participantId = participant.identity;
    final stats = _statsHistory[participantId];
    if (stats == null) return;

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final connectionStats = ConnectionStats(
      connectionQuality: participant.connectionQuality.toString(),
      isPublishing: participant is LocalParticipant
          ? participant.trackPublications.isNotEmpty
          : false,
      metadata: participant.metadata ?? '',
      publisherConnectionState: participant is LocalParticipant
          ? participant.room.engine.publisher?.pc.connectionState?.toString() ??
                ''
          : '',
      publisherIceState: participant is LocalParticipant
          ? participant.room.engine.publisher?.pc.iceConnectionState
                    ?.toString() ??
                ''
          : '',
      subscribedVideoTracks: participant is RemoteParticipant
          ? participant.videoTrackPublications
                .where((pub) => pub.subscribed)
                .length
          : 0,
      subscribedAudioTracks: participant is RemoteParticipant
          ? participant.audioTrackPublications
                .where((pub) => pub.subscribed)
                .length
          : 0,
    );

    stats.connectionStats[timestamp] = connectionStats;
  }

  void _logVideoSenderStats(String participantId, VideoSenderStatsEvent event) {
    final stats = _statsHistory[participantId];
    if (stats == null) return;

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final videoStats = VideoStats(
      bitrate: event.currentBitrate.toInt(),
      encoder:
          event.stats['f']?.encoderImplementation ??
          event.stats['h']?.encoderImplementation ??
          event.stats['q']?.encoderImplementation ??
          '',
      codec:
          event.stats['f']?.mimeType?.split('/')[1] ??
          event.stats['h']?.mimeType?.split('/')[1] ??
          event.stats['q']?.mimeType?.split('/')[1] ??
          '',
      payload:
          event.stats['f']?.payloadType?.toInt() ??
          event.stats['h']?.payloadType?.toInt() ??
          event.stats['q']?.payloadType?.toInt() ??
          0,
      qualityLimitationReason:
          event.stats['f']?.qualityLimitationReason ??
          event.stats['h']?.qualityLimitationReason ??
          event.stats['q']?.qualityLimitationReason ??
          '',
      qualityLimitationResolutionChanges:
          event.stats['f']?.qualityLimitationResolutionChanges?.toInt() ??
          event.stats['h']?.qualityLimitationResolutionChanges?.toInt() ??
          event.stats['q']?.qualityLimitationResolutionChanges?.toInt() ??
          0,
      roundTripTime:
          (event.stats['f']?.roundTripTime ??
              event.stats['h']?.roundTripTime ??
              event.stats['q']?.roundTripTime ??
              0) *
          1000,
    );

    stats.videoStats[timestamp] = videoStats;
  }

  void _logVideoReceiverStats(
    String participantId,
    VideoReceiverStatsEvent event,
  ) {
    final stats = _statsHistory[participantId];
    if (stats == null) return;

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final videoStats = VideoStats(
      bitrate: event.currentBitrate.toInt(),
      packetsLost: event.stats.packetsLost?.toInt() ?? 0,
      packetsReceived: event.stats.packetsReceived?.toInt() ?? 0,
      frameRate: event.stats.framesPerSecond?.toDouble() ?? 0,
      frameWidth: event.stats.frameWidth?.toInt() ?? 0,
      frameHeight: event.stats.frameHeight?.toInt() ?? 0,
      codec: event.stats.mimeType?.split('/')[1] ?? '',
      payload: event.stats.payloadType?.toInt() ?? 0,
    );

    stats.videoStats[timestamp] = videoStats;
  }

  void _logAudioSenderStats(String participantId, AudioSenderStatsEvent event) {
    final stats = _statsHistory[participantId];
    if (stats == null) return;

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final audioStats = AudioStats(
      bitrate: event.currentBitrate.toInt(),
      codec: event.stats.mimeType?.split('/')[1] ?? '',
      payload: event.stats.payloadType?.toInt() ?? 0,
      roundTripTime: (event.stats.roundTripTime ?? 0) * 1000,
      packetsLost: event.stats.packetsLost?.toInt() ?? 0,
      packetsSent: event.stats.packetsSent?.toInt() ?? 0,
    );

    stats.audioStats[timestamp] = audioStats;
  }

  void _logAudioReceiverStats(
    String participantId,
    AudioReceiverStatsEvent event,
  ) {
    final stats = _statsHistory[participantId];
    if (stats == null) return;

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final audioStats = AudioStats(
      bitrate: event.currentBitrate.toInt(),
      packetsLost: event.stats.packetsLost?.toInt() ?? 0,
      packetsReceived: event.stats.packetsReceived?.toInt() ?? 0,
      codec: event.stats.mimeType?.split('/')[1] ?? '',
      payload: event.stats.payloadType?.toInt() ?? 0,
      jitter: event.stats.jitter?.toDouble() ?? 0,
      concealedSamples: event.stats.concealedSamples?.toInt() ?? 0,
      concealmentEvents: event.stats.concealmentEvents?.toInt() ?? 0,
    );

    stats.audioStats[timestamp] = audioStats;
  }

  void logSystemLog(int timestamp, String log) {
    systemLogs.add(SystemLog(timestamp: timestamp, log: log));
  }

  // Get statistics for a specific participant
  ParticipantStats? getParticipantStats(String participantId) {
    return _statsHistory[participantId];
  }

  // Clear statistics for a specific participant
  void clearParticipantStats(String participantId) {
    final stats = _statsHistory[participantId];
    if (stats != null) {
      stats.videoStats.clear();
      stats.audioStats.clear();
      stats.connectionStats.clear();
    }
    systemLogs.clear();
  }

  // Clear all statistics
  void clearAllStats() {
    for (var stats in _statsHistory.values) {
      stats.videoStats.clear();
      stats.audioStats.clear();
      stats.connectionStats.clear();
    }
  }

  // Remove participant
  void removeParticipant(String participantId) {
    // Clean up listeners
    _participantListeners[participantId]?.forEach((listener) {
      listener.dispose();
    });
    _participantListeners.remove(participantId);

    _connectionListeners[participantId]?.dispose();
    _connectionListeners.remove(participantId);
  }

  // Clean up all resources
  void dispose() {
    for (var listeners in _participantListeners.values) {
      for (var listener in listeners) {
        listener.dispose();
      }
    }
    _participantListeners.clear();

    for (var listener in _connectionListeners.values) {
      listener.dispose();
    }
    _connectionListeners.clear();

    clearAllStats();
    systemLogs.clear();
  }

  // Export all statistics as JSON
  String exportAllStatsAsJson() {
    final Map<String, dynamic> jsonData = {};
    for (var entry in _statsHistory.entries) {
      jsonData[entry.key] = entry.value.toJson();
    }
    jsonData['SystemLogs'] = systemLogs.map((log) => log.toJson()).toList();
    return jsonEncode(jsonData);
  }

  // Export specific participant's statistics as JSON
  String? exportParticipantStatsAsJson(String participantId) {
    final stats = _statsHistory[participantId];
    if (stats == null) return null;
    return jsonEncode(stats.toJson());
  }

  // Export statistics for a specific time range
  String exportStatsInRangeAsJson(
    String participantId,
    int startTime,
    int endTime,
  ) {
    final stats = _statsHistory[participantId];
    if (stats == null) return '{}';

    final Map<String, dynamic> jsonData = {
      'participantId': stats.participantId,
      'name': stats.participantId,
      'isLocal': stats.isLocal,
      'videoStats': _filterStatsByTimeRange(
        stats.videoStats,
        startTime,
        endTime,
      ),
      'audioStats': _filterStatsByTimeRange(
        stats.audioStats,
        startTime,
        endTime,
      ),
      'connectionStats': _filterStatsByTimeRange(
        stats.connectionStats,
        startTime,
        endTime,
      ),
    };

    return jsonEncode(jsonData);
  }

  Map<String, dynamic> _filterStatsByTimeRange<T>(
    Map<int, T> stats,
    int startTime,
    int endTime,
  ) {
    return stats.entries
        .where((entry) => entry.key >= startTime && entry.key <= endTime)
        .fold<Map<String, dynamic>>({}, (map, entry) {
          map[entry.key.toString()] = entry.value is VideoStats
              ? (entry.value as VideoStats).toJson()
              : entry.value is AudioStats
              ? (entry.value as AudioStats).toJson()
              : (entry.value as ConnectionStats).toJson();
          return map;
        });
  }
}
