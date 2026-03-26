import 'dart:async';

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
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _RemoteParticipantWidgetState();
}

abstract class _ParticipantWidgetState<T extends ParticipantWidget>
    extends State<T> {
  VideoTrack? get activeVideoTrack;

  AudioTrack? get activeAudioTrack;

  TrackPublication? get videoPublication;

  TrackPublication? get audioPublication;

  bool get isScreenShare => widget.type == ParticipantTrackType.kScreenShare;
  EventsListener<ParticipantEvent>? _listener;
  ParticipantReaction? _currentReaction;
  String? _displayReactionEmoji;
  Timer? _hideReactionTimer;

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
    _syncReactionFromWidget();
    _onParticipantChanged();
  }

  @override
  void dispose() {
    widget.participant.removeListener(_onParticipantChanged);
    _listener?.dispose();
    _hideReactionTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    oldWidget.participant.removeListener(_onParticipantChanged);
    widget.participant.addListener(_onParticipantChanged);
    _syncReactionFromWidget();
    _onParticipantChanged();
    super.didUpdateWidget(oldWidget);
  }

  void _syncReactionFromWidget() {
    final incoming = widget.reaction;
    if (incoming == null) {
      if (_displayReactionEmoji == null && _currentReaction == null) {
        return;
      }
      _hideReactionTimer?.cancel();
      _currentReaction = null;
      setState(() {
        _displayReactionEmoji = null;
      });
      return;
    }
    if (_currentReaction?.timestamp == incoming.timestamp) return;

    _currentReaction = incoming;
    _hideReactionTimer?.cancel();
    setState(() {
      _displayReactionEmoji = incoming.emoji;
    });

    _hideReactionTimer = Timer(
      const Duration(milliseconds: reactionDisplayDurationMs),
      () {
        if (!mounted) return;
        if (_currentReaction?.timestamp != incoming.timestamp) return;
        setState(() {
          _displayReactionEmoji = null;
        });
      },
    );
  }

  // Notify Flutter that UI re-build is required, but we don't set anything here
  // since the updated values are computed properties.
  void _onParticipantChanged() => setState(() {});

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
              radius: 16,
              backgroundColor: context.colors.backgroundNorm,
              child: context.images.iconConnectionPoor.svg(
                width: 16,
                height: 16,
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
                ),
            ],
          ),
        ),
        // Top right: Connection quality icon + Audio status
        Positioned(top: 0, right: 0, child: _buildTopRightWidgets(ctx)),
        // Top left: Emoji reaction
        Positioned(
          top: 12,
          left: 12,
          child: IgnorePointer(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              reverseDuration: const Duration(milliseconds: 160),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) {
                final offsetAnimation = Tween<Offset>(
                  begin: const Offset(0, 0.12),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: offsetAnimation,
                    child: ScaleTransition(scale: animation, child: child),
                  ),
                );
              },
              child: widget.isRaisedHand
                  ? Text(raisedHandEmoji, style: TextStyle(fontSize: 30))
                  : _displayReactionEmoji == null
                  ? const SizedBox.shrink(key: ValueKey('no-reaction'))
                  : Text(
                      _displayReactionEmoji!,
                      style: const TextStyle(fontSize: 30),
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
