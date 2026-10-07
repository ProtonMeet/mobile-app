import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/views/components/safe_video_track_renderer.dart';
import 'package:meet/views/scenes/room/get_participant_display_colors.dart';

import 'no_video.dart';
import 'participant_info.dart';
import 'participant_stats.dart';

class ParticipantReaction {
  final String emoji;
  final int timestamp;

  const ParticipantReaction({required this.emoji, required this.timestamp});
}

abstract class ParticipantWidget extends StatefulWidget {
  // Convenience method to return relevant widget for participant
  static ParticipantWidget widgetFor(
    double widgetWidth,
    double widgetHeight,
    ParticipantDisplayColors participantDisplayColors,
    ParticipantInfo participantTrack, {
    required bool showStatsLayer,
    bool roundedBorder = true,
    bool isFullScreen = false,
    ParticipantReaction? reaction,
    bool isRaisedHand = false,
    bool compactOverlay = false,
    bool isPipMode = false,
    VoidCallback? onLowerHand,
  }) {
    if (participantTrack.participant is LocalParticipant) {
      return LocalParticipantWidget(
        participantTrack.displayName,
        participantTrack.participant as LocalParticipant,
        participantTrack.type,
        widgetWidth,
        widgetHeight,
        participantDisplayColors,
        showStatsLayer: showStatsLayer,
        roundedBorder: roundedBorder,
        isFullScreen: isFullScreen,
        reaction: reaction,
        isRaisedHand: isRaisedHand,
        compactOverlay: compactOverlay,
        isPipMode: isPipMode,
        onLowerHand: onLowerHand,
      );
    } else if (participantTrack.participant is RemoteParticipant) {
      return RemoteParticipantWidget(
        participantTrack.displayName,
        participantTrack.participant as RemoteParticipant,
        participantTrack.type,
        widgetWidth,
        widgetHeight,
        participantDisplayColors,
        showStatsLayer: showStatsLayer,
        roundedBorder: roundedBorder,
        isFullScreen: isFullScreen,
        reaction: reaction,
        isRaisedHand: isRaisedHand,
        compactOverlay: compactOverlay,
        isPipMode: isPipMode,
        onLowerHand: onLowerHand,
      );
    }
    throw UnimplementedError('Unknown participant type');
  }

  // Must be implemented by child class
  abstract final String displayName;
  abstract final ParticipantDisplayColors displayColors;
  abstract final Participant participant;
  abstract final ParticipantTrackType type;
  abstract final bool showStatsLayer;
  abstract final double widgetWidth;
  abstract final double widgetHeight;
  abstract final bool roundedBorder;
  abstract final bool isFullScreen;
  abstract final ParticipantReaction? reaction;
  abstract final bool isRaisedHand;
  abstract final bool compactOverlay;
  abstract final bool isPipMode;
  abstract final VoidCallback? onLowerHand;
  final VideoQuality quality;

  const ParticipantWidget({this.quality = VideoQuality.MEDIUM, super.key});
}

class LocalParticipantWidget extends ParticipantWidget {
  @override
  final String displayName;
  @override
  final LocalParticipant participant;
  @override
  final ParticipantTrackType type;
  @override
  final bool showStatsLayer;
  @override
  final double widgetWidth;
  @override
  final double widgetHeight;
  @override
  final bool roundedBorder;
  @override
  final bool isFullScreen;
  @override
  final ParticipantReaction? reaction;
  @override
  final bool isRaisedHand;
  @override
  final bool compactOverlay;
  @override
  final bool isPipMode;
  @override
  final VoidCallback? onLowerHand;
  @override
  final ParticipantDisplayColors displayColors;

  const LocalParticipantWidget(
    this.displayName,
    this.participant,
    this.type,
    this.widgetWidth,
    this.widgetHeight,
    this.displayColors, {
    required this.showStatsLayer,
    required this.roundedBorder,
    this.isFullScreen = false,
    this.reaction,
    this.isRaisedHand = false,
    this.compactOverlay = false,
    this.isPipMode = false,
    this.onLowerHand,

    super.key,
  });

  @override
  State<StatefulWidget> createState() => _LocalParticipantWidgetState();
}

class RemoteParticipantWidget extends ParticipantWidget {
  @override
  final String displayName;
  @override
  final RemoteParticipant participant;
  @override
  final ParticipantTrackType type;
  @override
  final bool showStatsLayer;
  @override
  final double widgetWidth;
  @override
  final double widgetHeight;
  @override
  final bool roundedBorder;
  @override
  final bool isFullScreen;
  @override
  final ParticipantReaction? reaction;
  @override
  final bool isRaisedHand;
  @override
  final bool compactOverlay;
  @override
  final bool isPipMode;
  @override
  final VoidCallback? onLowerHand;
  @override
  final ParticipantDisplayColors displayColors;

  const RemoteParticipantWidget(
    this.displayName,
    this.participant,
    this.type,
    this.widgetWidth,
    this.widgetHeight,
    this.displayColors, {
    required this.showStatsLayer,
    required this.roundedBorder,
    this.isFullScreen = false,
    this.reaction,
    this.isRaisedHand = false,
    this.compactOverlay = false,
    this.isPipMode = false,
    this.onLowerHand,
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _RemoteParticipantWidgetState();
}

/// Snapshot of every participant-driven field that the tile's [build]
/// actually reads. Records auto-generate structural `==` / `hashCode`,
/// so we can bail out of [State.setState] when nothing visible changed.
///
/// LiveKit's `Participant` ChangeNotifier fires for every audio-level
/// tick, connection-quality probe, mute/unmute, track sub/unsub, etc.
/// In a 200-person room that easily reaches 200+ events/s — without
/// this diff we used to schedule a full tile rebuild for every one.
typedef _ParticipantSnapshot = ({
  bool isSpeaking,
  ConnectionQuality connectionQuality,
  String? audioPubSid,
  bool? audioMuted,
  bool? audioSubscribed,
  String? videoPubSid,
  bool? videoTrackMuted,
  bool hasVideoTrack,
});

abstract class _ParticipantWidgetState<T extends ParticipantWidget>
    extends State<T> {
  VideoTrack? get activeVideoTrack;

  AudioTrack? get activeAudioTrack;

  TrackPublication? get videoPublication;

  TrackPublication? get audioPublication;

  bool get isScreenShare => widget.type == ParticipantTrackType.kScreenShare;

  EventsListener<ParticipantEvent>? _listener;

  /// Last snapshot we rebuilt against. `_onParticipantChanged` short-circuits
  /// when the next snapshot is structurally equal to this.
  _ParticipantSnapshot? _lastSnapshot;

  /// Read every build-time input from the current participant + track state
  /// in one shot. Stays cheap (8 field reads, 1 record allocation).
  _ParticipantSnapshot _captureSnapshot() {
    final ap = audioPublication;
    final vp = videoPublication;
    final vt = activeVideoTrack;
    return (
      isSpeaking: widget.participant.isSpeaking,
      connectionQuality: widget.participant.connectionQuality,
      audioPubSid: ap?.sid,
      audioMuted: ap?.muted,
      audioSubscribed: ap?.subscribed,
      videoPubSid: vp?.sid,
      videoTrackMuted: vt?.muted,
      hasVideoTrack: vt != null,
    );
  }

  @override
  void initState() {
    super.initState();
    _listener = widget.participant.createListener();
    _listener?.on<TranscriptionEvent>((e) {
      for (var seg in e.segments) {
        l.logger.i('Transcription: ${seg.text} ${seg.isFinal}');
      }
    });

    widget.participant.addListener(_onParticipantChanged);
    // Seed the snapshot. The first frame builds naturally after initState,
    // so we don't need an extra setState here.
    _lastSnapshot = _captureSnapshot();
  }

  @override
  void dispose() {
    widget.participant.removeListener(_onParticipantChanged);
    _listener?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    oldWidget.participant.removeListener(_onParticipantChanged);
    widget.participant.addListener(_onParticipantChanged);
    // didUpdateWidget always implies a rebuild, so just refresh the snapshot
    // baseline against the (potentially new) participant.
    _lastSnapshot = _captureSnapshot();
    super.didUpdateWidget(oldWidget);
  }

  /// Diff the current snapshot against the last one we rebuilt against and
  /// only `setState` when something visible actually changed. LiveKit fires
  /// this for every audio-level tick, so 80–90% of calls in a busy room
  /// short-circuit here without touching the widget tree.
  void _onParticipantChanged() {
    final next = _captureSnapshot();
    if (next == _lastSnapshot) return;
    _lastSnapshot = next;
    if (!mounted) return;
    setState(() {});
  }

  // Widgets to show above the info bar
  List<Widget> extraWidgets({required bool isScreenShare}) => [];

  /// Check if connection quality is poor
  bool get _shouldShowConnectionQualityIcon {
    final quality = widget.participant.connectionQuality;

    return quality == ConnectionQuality.poor ||
        quality == ConnectionQuality.lost;
  }

  /// Build top right widgets (connection quality icon + audio status)
  Widget _buildTopRightWidgets(BuildContext context) {
    final avatarRadius = widget.compactOverlay ? 10.0 : 16.0;
    final iconSize = widget.compactOverlay ? 10.0 : 16.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Connection quality icon (for participants with poor quality)
        if (_shouldShowConnectionQualityIcon)
          Tooltip(
            message: context.local.connection_quality_poor,
            triggerMode: TooltipTriggerMode.tap,
            constraints: BoxConstraints(minHeight: 40),
            textStyle: ProtonStyles.body2Medium(color: context.colors.textNorm),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: context.colors.backgroundNorm,
              borderRadius: BorderRadius.circular(16),
            ),
            child: CircleAvatar(
              radius: avatarRadius,
              backgroundColor: context.colors.signalDangerMajor3,
              child: context.images.iconConnectionPoor.svg(
                width: iconSize,
                height: iconSize,
              ),
            ),
          ),
        // Audio status (mic icon)
        ParticipantInfoWidget(
          audioAvailable:
              audioPublication?.muted == false &&
              audioPublication?.subscribed == true,
          isScreenShare: isScreenShare,
          type: ParticipantInfoType.kAudioStatus,
          activeAudioTrack: activeAudioTrack,
          compact: widget.compactOverlay,
          isPipMode: widget.isPipMode,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext ctx) => Container(
    foregroundDecoration: BoxDecoration(
      border: widget.participant.isSpeaking && !isScreenShare
          ? Border.all(width: 2.4, color: context.colors.protonBlue)
          : null,
      borderRadius: BorderRadius.circular(widget.roundedBorder ? 24 : 0),
    ),
    decoration: BoxDecoration(color: Colors.transparent),
    child: Stack(
      children: [
        // Video
        DecoratedBox(
          decoration: BoxDecoration(
            color: context.colors.backgroundSecondary,
            borderRadius: BorderRadius.circular(widget.roundedBorder ? 24 : 0),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.roundedBorder ? 24 : 0),
            child: Center(
              child: activeVideoTrack != null && !activeVideoTrack!.muted
                  ? SafeVideoTrackRenderer(
                      fit: isScreenShare
                          ? VideoViewFit.contain
                          : VideoViewFit.cover,
                      videoTrack: activeVideoTrack!,
                    )
                  : NoVideoWidget(
                      name: widget.displayName,
                      displayColors: widget.displayColors,
                    ),
            ),
          ),
        ),
        // Bottom bar
        Align(
          alignment: Alignment.bottomCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              ...extraWidgets(isScreenShare: isScreenShare),

              /// do not show name on screen share tile when in full screen
              if (!(isScreenShare && widget.isFullScreen))
                ParticipantInfoWidget(
                  title: widget.displayName,
                  audioAvailable:
                      audioPublication?.muted == false &&
                      audioPublication?.subscribed == true,
                  type: ParticipantInfoType.kName,
                  isScreenShare: isScreenShare,
                  compact: widget.compactOverlay,
                  isPipMode: widget.isPipMode,
                ),
            ],
          ),
        ),
        // Top right: Connection quality icon + Audio status
        Positioned(top: 0, right: 0, child: _buildTopRightWidgets(ctx)),
        // Top left: raised hand only (emoji reactions use ReactionStream).
        if (widget.isRaisedHand)
          Positioned(
            top: 12,
            left: 12,
            child: widget.onLowerHand == null
                ? const Text(raisedHandEmoji, style: TextStyle(fontSize: 30))
                : Tooltip(
                    message: ctx.local.lower_participant_hand,
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        onTap: widget.onLowerHand,
                        borderRadius: BorderRadius.circular(999),
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: Text(
                            raisedHandEmoji,
                            style: TextStyle(fontSize: 30),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        if (widget.showStatsLayer)
          Positioned(
            top: 130,
            right: 30,
            child: ParticipantStatsWidget(participant: widget.participant),
          ),
      ],
    ),
  );
}

class _LocalParticipantWidgetState
    extends _ParticipantWidgetState<LocalParticipantWidget> {
  @override
  LocalTrackPublication<LocalVideoTrack>? get videoPublication => widget
      .participant
      .videoTrackPublications
      .where((element) => element.source == widget.type.lkVideoSourceType)
      .firstOrNull;

  @override
  LocalTrackPublication<LocalAudioTrack>? get audioPublication => widget
      .participant
      .audioTrackPublications
      .where((element) => element.source == widget.type.lkAudioSourceType)
      .firstOrNull;

  @override
  VideoTrack? get activeVideoTrack => videoPublication?.track;

  @override
  AudioTrack? get activeAudioTrack => audioPublication?.track;
}

class _RemoteParticipantWidgetState
    extends _ParticipantWidgetState<RemoteParticipantWidget> {
  @override
  RemoteTrackPublication<RemoteVideoTrack>? get videoPublication => widget
      .participant
      .videoTrackPublications
      .where((element) => element.source == widget.type.lkVideoSourceType)
      .firstOrNull;

  @override
  RemoteTrackPublication<RemoteAudioTrack>? get audioPublication => widget
      .participant
      .audioTrackPublications
      .where((element) => element.source == widget.type.lkAudioSourceType)
      .firstOrNull;

  @override
  VideoTrack? get activeVideoTrack => videoPublication?.track;

  @override
  AudioTrack? get activeAudioTrack => audioPublication?.track;

  @override
  List<Widget> extraWidgets({required bool isScreenShare}) => [
    Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // // Menu for RemoteTrackPublication<RemoteAudioTrack>
        // if (audioPublication != null)
        //   RemoteTrackPublicationMenuWidget(
        //     pub: audioPublication!,
        //     icon: Icons.volume_up,
        //   ),
        // // Menu for RemoteTrackPublication<RemoteVideoTrack>
        // if (videoPublication != null)
        //   RemoteTrackPublicationMenuWidget(
        //     pub: videoPublication!,
        //     icon: isScreenShare ? Icons.monitor : Icons.videocam,
        //   ),
        // if (videoPublication != null)
        //   RemoteTrackFPSMenuWidget(
        //     pub: videoPublication!,
        //     icon: Icons.menu,
        //   ),
        // if (videoPublication != null)
        //   RemoteTrackQualityMenuWidget(
        //     pub: videoPublication!,
        //     icon: Icons.monitor_outlined,
        //   ),
      ],
    ),
  ];
}

class RemoteTrackPublicationMenuWidget extends StatelessWidget {
  final IconData icon;
  final RemoteTrackPublication pub;

  const RemoteTrackPublicationMenuWidget({
    required this.pub,
    required this.icon,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black.withValues(alpha: 0.3),
    child: PopupMenuButton<Function>(
      tooltip: context.local.subscribe_menu,
      icon: Icon(
        icon,
        color: {
          TrackSubscriptionState.notAllowed: Colors.red,
          TrackSubscriptionState.unsubscribed: Colors.grey,
          TrackSubscriptionState.subscribed: Colors.green,
        }[pub.subscriptionState],
      ),
      onSelected: (value) => value(),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<Function>>[
        // Subscribe/Unsubscribe
        if (!pub.subscribed)
          PopupMenuItem(
            value: pub.subscribe,
            child: Text(context.local.subscribe),
          )
        else if (pub.subscribed)
          PopupMenuItem(
            value: pub.unsubscribe,
            child: Text(context.local.unsubscribe),
          ),
      ],
    ),
  );
}

class RemoteTrackFPSMenuWidget extends StatelessWidget {
  final IconData icon;
  final RemoteTrackPublication pub;

  const RemoteTrackFPSMenuWidget({
    required this.pub,
    required this.icon,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black.withValues(alpha: 0.3),
    child: PopupMenuButton<Function>(
      tooltip: context.local.preferred_fps,
      icon: Icon(icon, color: Colors.white),
      onSelected: (value) => value(),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<Function>>[
        PopupMenuItem(
          child: const Text('30'),
          value: () => pub.setVideoFPS(30),
        ),
        PopupMenuItem(
          child: const Text('15'),
          value: () => pub.setVideoFPS(15),
        ),
        PopupMenuItem(child: const Text('8'), value: () => pub.setVideoFPS(8)),
      ],
    ),
  );
}

class RemoteTrackQualityMenuWidget extends StatelessWidget {
  final IconData icon;
  final RemoteTrackPublication pub;

  const RemoteTrackQualityMenuWidget({
    required this.pub,
    required this.icon,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black.withValues(alpha: 0.3),
    child: PopupMenuButton<Function>(
      tooltip: context.local.preferred_quality,
      icon: Icon(icon, color: Colors.white),
      onSelected: (value) => value(),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<Function>>[
        PopupMenuItem(
          child: Text(context.local.high),
          value: () => pub.setVideoQuality(VideoQuality.HIGH),
        ),
        PopupMenuItem(
          child: Text(context.local.medium),
          value: () => pub.setVideoQuality(VideoQuality.MEDIUM),
        ),
        PopupMenuItem(
          child: Text(context.local.low),
          value: () => pub.setVideoQuality(VideoQuality.LOW),
        ),
      ],
    ),
  );
}
