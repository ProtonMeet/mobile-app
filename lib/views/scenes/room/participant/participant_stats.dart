// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

enum StatsType {
  kUnknown,
  kLocalAudioSender,
  kLocalVideoSender,
  kRemoteAudioReceiver,
  kRemoteVideoReceiver,
}

class ParticipantStatsWidget extends StatefulWidget {
  const ParticipantStatsWidget({required this.participant, super.key});
  final Participant participant;
  @override
  State<StatefulWidget> createState() => _ParticipantStatsWidgetState();
}

class _ParticipantStatsWidgetState extends State<ParticipantStatsWidget> {
  final List<EventsListener<TrackEvent>> _listeners = [];
  EventsListener<ParticipantEvent>? _participantListener;
  final Map<String, Map<String, String>> _stats = {
    'connection': {},
    'audio': {},
    'video': {},
    'screen-share': {},
    'local': {},
  };
  final Set<String> _videoTrackIds = {};
  bool _disposed = false;

  void _setUpListener(Track track) {
    final listener = track.createListener();
    _listeners.add(listener);

    if (track is LocalVideoTrack) {
      listener.on<VideoSenderStatsEvent>(
        (event) => _handleLocalVideoStats(event, track),
      );
    } else if (track is RemoteVideoTrack) {
      listener.on<VideoReceiverStatsEvent>(_handleRemoteVideoStats);
    } else if (track is LocalAudioTrack) {
      listener.on<AudioSenderStatsEvent>(_handleLocalAudioStats);
    } else if (track is RemoteAudioTrack) {
      listener.on<AudioReceiverStatsEvent>(_handleRemoteAudioStats);
    }
  }

  void _handleLocalVideoStats(
    VideoSenderStatsEvent event,
    LocalVideoTrack track,
  ) {
    if (_disposed) return;

    final Map<String, String> stats = {};
    stats['tx'] = 'total sent ${event.currentBitrate.toInt()} kpbs';

    event.stats.forEach((key, value) {
      stats['layer-$key'] =
          '${value.frameWidth ?? 0}x${value.frameHeight ?? 0} ${value.framesPerSecond?.toDouble() ?? 0} fps, ${event.bitrateForLayers[key] ?? 0} kbps';
    });

    final firstStats = event.stats['f'] ?? event.stats['h'] ?? event.stats['q'];
    if (firstStats != null) {
      stats['encoder'] = firstStats.encoderImplementation ?? '';
      if (firstStats.mimeType != null) {
        stats['codec'] =
            '${firstStats.mimeType!.split('/')[1]}/${firstStats.clockRate}';
      }
      stats['payload'] = '${firstStats.payloadType}';
      stats['qualityLimitationReason'] =
          firstStats.qualityLimitationReason ?? 'none';
      stats['qualityLimitationResolutionChanges'] =
          '${firstStats.qualityLimitationResolutionChanges ?? 0}';

      if (firstStats.roundTripTime != null) {
        stats['RTT'] =
            '${(firstStats.roundTripTime! * 1000).toStringAsFixed(2)} ms';
      }

      final String trackKey = track.source == TrackSource.screenShareVideo
          ? 'screen-share'
          : 'local';

      setState(() {
        _videoTrackIds.add(trackKey);
        _stats[trackKey]!.addEntries(stats.entries);
      });
    }
  }

  void _handleRemoteVideoStats(VideoReceiverStatsEvent event) {
    if (_disposed) return;

    final Map<String, String> stats = {};
    if (!event.currentBitrate.isFinite && !event.currentBitrate.isNaN) {
      stats['rx'] = '${event.currentBitrate.toInt()} kpbs';
    }

    if (event.stats.mimeType != null) {
      stats['codec'] =
          '${event.stats.mimeType!.split('/')[1]}/${event.stats.clockRate}';
    }

    stats['payload'] = '${event.stats.payloadType}';
    stats['size/fps'] =
        '${event.stats.frameWidth}x${event.stats.frameHeight} ${event.stats.framesPerSecond?.toDouble()}fps';
    stats['jitter'] = '${event.stats.jitter} s';
    stats['decoder'] = '${event.stats.decoderImplementation}';
    stats['video packets lost'] = '${event.stats.packetsLost}';
    stats['video packets received'] = '${event.stats.packetsReceived}';
    stats['frames received'] = '${event.stats.framesReceived}';
    stats['frames decoded'] = '${event.stats.framesDecoded}';
    stats['frames dropped'] = '${event.stats.framesDropped}';

    if (event.stats.packetsReceived != null &&
        event.stats.packetsReceived! > 0 &&
        event.stats.packetsLost != null) {
      final lossRate =
          (event.stats.packetsLost! * 100.0) /
          (event.stats.packetsLost! + event.stats.packetsReceived!);
      stats['packet loss rate'] = '${lossRate.toStringAsFixed(2)}%';
    }

    setState(() {
      _stats['video']!.addEntries(stats.entries);
    });
  }

  void _handleLocalAudioStats(AudioSenderStatsEvent event) {
    if (_disposed) return;

    final Map<String, String> stats = {};
    stats['tx'] = '${event.currentBitrate.toInt()} kpbs';

    if (event.stats.mimeType != null) {
      stats['codec'] =
          '${event.stats.mimeType!.split('/')[1]}/${event.stats.clockRate}/${event.stats.channels}';
    }

    stats['payload'] = '${event.stats.payloadType}';

    if (event.stats.roundTripTime != null) {
      stats['RTT'] =
          '${(event.stats.roundTripTime! * 1000).toStringAsFixed(2)} ms';
    }

    setState(() {
      _stats['audio']!.addEntries(stats.entries);
    });
  }

  void _handleRemoteAudioStats(AudioReceiverStatsEvent event) {
    if (_disposed) return;

    final Map<String, String> stats = {};
    stats['rx'] = '${event.currentBitrate.toInt()} kpbs';

    if (event.stats.mimeType != null) {
      stats['codec'] =
          '${event.stats.mimeType!.split('/')[1]}/${event.stats.clockRate}/${event.stats.channels}';
    }

    stats['payload'] = '${event.stats.payloadType}';
    stats['jitter'] = '${event.stats.jitter} s';
    stats['concealed samples'] =
        '${event.stats.concealedSamples ?? 0} / ${event.stats.concealmentEvents ?? 0}';
    stats['packets lost'] = '${event.stats.packetsLost}';
    stats['packets received'] = '${event.stats.packetsReceived}';

    if (event.stats.packetsReceived != null &&
        event.stats.packetsReceived! > 0 &&
        event.stats.packetsLost != null) {
      final lossRate =
          (event.stats.packetsLost! * 100.0) /
          (event.stats.packetsLost! + event.stats.packetsReceived!);
      stats['packet loss rate'] = '${lossRate.toStringAsFixed(2)}%';
    }

    setState(() {
      _stats['audio']!.addEntries(stats.entries);
    });
  }

  void _setupParticipantListener() {
    _participantListener = widget.participant.createListener();

    // Update connection information at setup
    _updateConnectionInfo();

    // Listen for general participant events that might impact stats
    _participantListener?.on<ParticipantEvent>((event) {
      if (!_disposed) {
        _updateConnectionInfo();
      }
    });
  }

  void _updateConnectionInfo() {
    if (_disposed) return;

    final Map<String, String> connectionStats = {};

    // Connection quality
    connectionStats['connection quality'] = widget.participant.connectionQuality
        .toString();

    // Add participant connection state
    if (widget.participant is LocalParticipant) {
      final localParticipant = widget.participant as LocalParticipant;
      connectionStats['is publishing'] = localParticipant
          .trackPublications
          .isNotEmpty
          .toString();

      try {
        final room = localParticipant.room;
        if (room.engine.publisher?.pc != null) {
          connectionStats['publisher connection state'] =
              room.engine.publisher?.pc.connectionState?.toString() ??
              'unknown';
          connectionStats['publisher ICE state'] =
              room.engine.publisher?.pc.iceConnectionState?.toString() ??
              'unknown';
        }
      } catch (e) {
        connectionStats['connection error'] = e.toString();
      }
    }

    // Add participant metadata if available
    if (widget.participant.metadata != null &&
        widget.participant.metadata!.isNotEmpty) {
      connectionStats['metadata'] = widget.participant.metadata!;
    }

    // Add stream state information for remote participants
    if (widget.participant is RemoteParticipant) {
      final remoteParticipant = widget.participant as RemoteParticipant;
      final videoSubs = remoteParticipant.videoTrackPublications
          .where((pub) => pub.subscribed)
          .length;
      final audioSubs = remoteParticipant.audioTrackPublications
          .where((pub) => pub.subscribed)
          .length;

      connectionStats['subscribed video tracks'] =
          '$videoSubs/${remoteParticipant.videoTrackPublications.length}';
      connectionStats['subscribed audio tracks'] =
          '$audioSubs/${remoteParticipant.audioTrackPublications.length}';
    }

    setState(() {
      _stats['connection']!.clear();
      _stats['connection']!.addEntries(connectionStats.entries);
    });
  }

  void _onParticipantChanged() {
    if (_disposed) return;

    for (final element in _listeners) {
      element.dispose();
    }
    _listeners.clear();

    // Update connection info
    _updateConnectionInfo();

    // Setup listeners for all tracks
    for (final track in [
      ...widget.participant.videoTrackPublications,
      ...widget.participant.audioTrackPublications,
    ]) {
      if (track.track != null) {
        _setUpListener(track.track!);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _disposed = false;
    widget.participant.addListener(_onParticipantChanged);
    _setupParticipantListener();
    // trigger initial change
    _onParticipantChanged();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final element in _listeners) {
      element.dispose();
    }
    _participantListener?.dispose();
    widget.participant.removeListener(_onParticipantChanged);
    super.dispose();
  }

  Color _getQualityColor(String quality) {
    switch (quality.toLowerCase()) {
      case 'excellent':
        return context.colors.notificationSuccess;
      case 'good':
        return Colors.orange;
      case 'poor':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      clipBehavior: Clip.antiAlias,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Container(
        width: double.infinity,
        color: Colors.black.withAlpha(75),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStatsSection('connection info', _stats['connection']!),
            const SizedBox(height: 8),
            _buildStatsSection('audio stats', _stats['audio']!),
            const SizedBox(height: 8),
            const Text(
              'video stats',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            if (_videoTrackIds.isEmpty)
              ..._stats['video']!.entries.map(
                (e) => Row(
                  children: [
                    Text(
                      '${e.key}: ',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Flexible(
                      child: Text(
                        e.value,
                        style:
                            e.key == 'qualityLimitationReason' &&
                                e.value != 'none'
                            ? const TextStyle(color: Colors.orange)
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            if (_videoTrackIds.isNotEmpty)
              for (final trackId in _videoTrackIds)
                _buildVideoStatsSection(trackId, _stats[trackId]!),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsSection(String title, Map<String, String> statsMap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        ...statsMap.entries.map(
          (e) => _buildStatRow(
            e.key,
            e.value,
            specialStyle:
                title == 'connection info' && e.key == 'connection quality'
                ? TextStyle(color: _getQualityColor(e.value))
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildVideoStatsSection(String title, Map<String, String> statsMap) {
    if (statsMap.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        ...statsMap.entries.map((e) => _buildStatRow(e.key, e.value)),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildStatRow(String key, String value, {TextStyle? specialStyle}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$key: ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Flexible(child: Text(value, style: specialStyle)),
        ],
      ),
    );
  }
}
