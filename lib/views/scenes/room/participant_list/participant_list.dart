import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/frb_upcoming_meeting.dart';
import 'package:meet/helper/local_toast.dart';

import 'package:meet/rust/proton_meet/models/meeting_info.dart';
import 'package:meet/views/scenes/room/get_participant_display_colors.dart';
import 'package:meet/views/scenes/room/participant_list/waiting_room_host_participant_list.dart';
import 'package:meet/views/scenes/room/room_bloc.dart';
import 'package:meet/views/scenes/room/room_state.dart';
import 'package:meet/views/scenes/room/side_panel_widget.dart';
import 'package:meet/views/scenes/utils.dart';
import 'package:meet/views/scenes/widgets/icon.button.with.actions.dart';

enum ParticipantListPresentation { sheet, embeddedScrollView }

class ParticipantListLayoutConstants {
  static const double headerHeight = 52.0;
  static const double tabBarHeight = 52.0;
  static const double handleHeight = 36.0;
  static const double avatarSize = 40.0;
  static const double actionButtonSize = 32.0;
  static const double actionIconSize = 16.0;
  static const double participantItemHeight = 64.0;
  static const double horizontalPadding = 24.0;
  static const double verticalPadding = 12.0;
  static const double spacingSmall = 4.0;
  static const double spacingMedium = 8.0;
  static const double spacingLarge = 16.0;
  static const double borderRadiusMedium = 24.0;
  static const double borderRadiusAvatar = 20002.0;
}

class ParticipantList extends StatelessWidget {
  const ParticipantList({
    required this.participants,
    required this.onTapParticipantVideoLocalAction,
    this.onTapParticipantAudioLocalAction,
    this.onTapParticipantVideoRemoteAction,
    this.onTapParticipantAudioRemoteAction,
    this.waitingParticipants = const [],
    this.isHost = false,
    super.key,
  });

  final List<ParticipantDetail> participants;
  final List<WaitingRoomParticipantDetail> waitingParticipants;
  final void Function(Participant<TrackPublication<Track>>? participant)
  onTapParticipantVideoLocalAction;
  final void Function(Participant<TrackPublication<Track>>? participant)?
  onTapParticipantAudioLocalAction;
  final void Function(Participant<TrackPublication<Track>>? participant)?
  onTapParticipantVideoRemoteAction;
  final void Function(Participant<TrackPublication<Track>>? participant)?
  onTapParticipantAudioRemoteAction;
  final bool isHost;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<RoomBloc, RoomState, bool>(
      selector: (state) {
        final hasWaitingRoom =
            state.meetingInfo?.waitingRoom.isWaitingRoomEnabled ?? false;
        return isHost && hasWaitingRoom;
      },
      builder: (context, showWaitingRoomHostList) {
        if (showWaitingRoomHostList) {
          return WaitingRoomHostParticipantList(
            participants: participants,
            waitingParticipants: waitingParticipants,
            onTapParticipantVideoLocalAction: onTapParticipantVideoLocalAction,
            onTapParticipantAudioLocalAction: onTapParticipantAudioLocalAction,
            onTapParticipantVideoRemoteAction:
                onTapParticipantVideoRemoteAction,
            onTapParticipantAudioRemoteAction:
                onTapParticipantAudioRemoteAction,
            isHost: isHost,
          );
        }

        return ParticipantListBody(
          participants: participants,
          onTapParticipantVideoLocalAction: onTapParticipantVideoLocalAction,
          onTapParticipantAudioLocalAction: onTapParticipantAudioLocalAction,
          onTapParticipantVideoRemoteAction: onTapParticipantVideoRemoteAction,
          onTapParticipantAudioRemoteAction: onTapParticipantAudioRemoteAction,
          isHost: isHost,
        );
      },
    );
  }
}

class ParticipantListBody extends StatefulWidget {
  const ParticipantListBody({
    required this.participants,
    required this.onTapParticipantVideoLocalAction,
    this.onTapParticipantAudioLocalAction,
    this.onTapParticipantVideoRemoteAction,
    this.onTapParticipantAudioRemoteAction,
    this.isHost = false,
    this.presentation = ParticipantListPresentation.sheet,
    super.key,
  });

  final List<ParticipantDetail> participants;
  final void Function(Participant<TrackPublication<Track>>? participant)
  onTapParticipantVideoLocalAction;
  final void Function(Participant<TrackPublication<Track>>? participant)?
  onTapParticipantAudioLocalAction;
  final void Function(Participant<TrackPublication<Track>>? participant)?
  onTapParticipantVideoRemoteAction;
  final void Function(Participant<TrackPublication<Track>>? participant)?
  onTapParticipantAudioRemoteAction;
  final bool isHost;
  final ParticipantListPresentation presentation;

  @override
  State<ParticipantListBody> createState() => _ParticipantListBodyState();
}

class _ParticipantListBodyState extends State<ParticipantListBody> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, bool> _showMoreButton = {};
  final Map<String, ({Color backgroundColor, Color profileTextColor})>
  _colorCache = {};
  final Map<String, String> _initialsCache = {};

  List<ParticipantDetail> get _filteredParticipants => widget.participants;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ParticipantListBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.participants.length != oldWidget.participants.length) {
      _colorCache.clear();
      _initialsCache.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.presentation == ParticipantListPresentation.embeddedScrollView) {
      final participants = _filteredParticipants;
      if (participants.isEmpty) {
        return _buildEmptyState(context);
      }

      return ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: participants.length,
        itemBuilder: (context, index) {
          return _buildParticipantItem(context, participants[index]);
        },
      );
    }

    return RoomSidePanelScroll(
      scrollController: _scrollController,
      header: _buildHeaderTitleRow(context),
      slivers: _buildSlivers(context),
    );
  }

  List<Widget> _buildSlivers(BuildContext context) {
    final participants = _filteredParticipants;
    return [
      SliverToBoxAdapter(
        child: BlocSelector<RoomBloc, RoomState, (bool, bool, FrbMeetingInfo?)>(
          selector: (state) =>
              (state.isHost, state.isPaidUser, state.meetingInfo),
          builder: (context, data) {
            final isHost = data.$1;
            final isPaidUser = data.$2;
            final meetingInfo = data.$3;
            final participantCount = widget.participants.length;
            final isGuestMeetingRoom = _isGuestMeetingRoom(meetingInfo);

            if ((!isHost && !isGuestMeetingRoom) || meetingInfo == null) {
              return const SizedBox.shrink();
            }

            final isAtLimit = participantCount >= meetingInfo.maxParticipants;

            return Container(
              margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(
                  RoomSidePanelLayout.borderRadiusMedium,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isPaidUser
                        ? context.local.you_are_using_paid_meet_plan
                        : context.local.you_are_using_free_meet_plan,
                    style: ProtonStyles.body2Medium(
                      color: isAtLimit
                          ? context.colors.notificationError
                          : context.colors.protonBlue,
                    ),
                  ),
                  RichText(
                    text: TextSpan(
                      style: ProtonStyles.body2Regular(
                        color: context.colors.textWeak,
                      ),
                      children: [
                        TextSpan(
                          text: isAtLimit
                              ? context.local.call_reached_limit
                              : context.local.call_supports_up_to,
                        ),
                        TextSpan(
                          text: '${meetingInfo.maxParticipants}',
                          style: ProtonStyles.body2Regular(
                            color: context.colors.textWeak,
                          ),
                        ),
                        TextSpan(
                          text: isAtLimit
                              ? context.local.participants_reached_limit_suffix
                              : context.local.participants_suffix,
                        ),
                        if (isAtLimit) ...[
                          const TextSpan(text: '\n'),
                          TextSpan(
                            text: context.local.no_more_participants_can_join,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      if (participants.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: _buildEmptyState(context),
        )
      else
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final participant = participants[index];
              final key = participant.participant?.identity ?? participant.name;
              return RepaintBoundary(
                key: ValueKey(key),
                child: _buildParticipantItem(context, participant),
              );
            },
            childCount: participants.length,
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: false,
          ),
        ),
      SliverPadding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewPadding.bottom,
        ),
      ),
    ];
  }

  bool _isGuestMeetingRoom(FrbMeetingInfo? meetingInfo) {
    /// If the max participants is guestMeetingRoomSize (4 by default), it is a guest meeting room.
    return (meetingInfo?.maxParticipants ?? 0) == guestMeetingRoomSize;
  }

  Widget _buildHeaderTitleRow(BuildContext context) {
    return RepaintBoundary(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.local.show_participants_list,
            style: ProtonStyles.headline(
              fontSize: 18,
              color: context.colors.textNorm,
            ),
          ),
          const SizedBox(width: ParticipantListLayoutConstants.spacingSmall),
          BlocSelector<RoomBloc, RoomState, (FrbMeetingInfo?, bool)>(
            selector: (state) => (state.meetingInfo, state.isHost),
            builder: (context, data) {
              final meetingInfo = data.$1;
              final isHost = data.$2;
              final participantCount = widget.participants.length;
              final isGuestMeetingRoom = _isGuestMeetingRoom(meetingInfo);
              final countText =
                  (meetingInfo != null && (isHost || isGuestMeetingRoom))
                  ? '($participantCount/${meetingInfo.maxParticipants})'
                  : '($participantCount)';
              final isAtLimit =
                  meetingInfo != null &&
                  participantCount >= meetingInfo.maxParticipants;
              return Text(
                countText,
                style: ProtonStyles.headline(
                  fontSize: 16,
                  color: isHost
                      ? isAtLimit
                            ? context.colors.notificationError
                            : context.colors.textWeak
                      : context.colors.textWeak,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 48, color: context.colors.textHint),
          const SizedBox(height: ParticipantListLayoutConstants.spacingLarge),
          Text(
            context.local.no_participants_found,
            style: ProtonStyles.body1Medium(color: context.colors.textHint),
          ),
          const SizedBox(height: ParticipantListLayoutConstants.spacingMedium),
          Text(
            context.local.try_different_search_term,
            style: ProtonStyles.body2Regular(color: context.colors.textWeak),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantItem(BuildContext context, ParticipantDetail p) {
    final participantId = p.participant?.identity ?? p.name;
    final colors = _colorCache.putIfAbsent(participantId, () {
      final c = getParticipantDisplayColors(context, participantId.hashCode);
      return (
        backgroundColor: c.backgroundColor,
        profileTextColor: c.profileTextColor,
      );
    });

    final initials = _initialsCache.putIfAbsent(
      p.name,
      () => getInitials(p.name),
    );

    return GestureDetector(
      onLongPress: () {
        setState(() {
          _showMoreButton[p.name] = true;
        });
      },
      child: Container(
        width: double.infinity,
        height: ParticipantListLayoutConstants.participantItemHeight,
        padding: const EdgeInsets.only(
          top: ParticipantListLayoutConstants.verticalPadding,
          left: RoomSidePanelLayout.horizontalPadding,
          right: ParticipantListLayoutConstants.spacingSmall,
          bottom: ParticipantListLayoutConstants.verticalPadding,
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: ParticipantListLayoutConstants.avatarSize,
                    height: ParticipantListLayoutConstants.avatarSize,
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: ShapeDecoration(
                        color: colors.backgroundColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            ParticipantListLayoutConstants.borderRadiusAvatar,
                          ),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          initials,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colors.profileTextColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            height: 1.50,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(
                    width: ParticipantListLayoutConstants.spacingLarge,
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                p.name,
                                style: ProtonStyles.body2Medium(
                                  color: context.colors.textNorm,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (p.isRaisedHand)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Text(
                                  raisedHandEmoji,
                                  style: ProtonStyles.headline(
                                    color: context.colors.textNorm,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (p.isHost || p.isRecording)
                          Text(
                            _composeStatusLine(
                              isHost: p.isHost,
                              isRecording: p.isRecording,
                              recordingLabel: context.local.recording_label,
                            ),
                            style: ProtonStyles.body2Regular(
                              color: p.isRecording
                                  ? context.colors.signalDanger
                                  : context.colors.textWeak,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: ParticipantListLayoutConstants.spacingMedium),
            _buildActionButton(
              context,
              child: p.hasAudio
                  ? context.images.iconAudioOnWave.svg(
                      width: ParticipantListLayoutConstants.actionIconSize,
                      height: ParticipantListLayoutConstants.actionIconSize,
                      colorFilter: ColorFilter.mode(
                        context.colors.notificationSuccess,
                        BlendMode.srcIn,
                      ),
                    )
                  : context.images.iconAudioOff.svg(
                      width: ParticipantListLayoutConstants.actionIconSize,
                      height: ParticipantListLayoutConstants.actionIconSize,
                      colorFilter: ColorFilter.mode(
                        context.colors.signalDanger,
                        BlendMode.srcIn,
                      ),
                    ),
            ),
            const SizedBox(width: ParticipantListLayoutConstants.spacingMedium),
            _buildActionButton(
              context,
              child: p.hasVideo
                  ? context.images.iconVideoOn.svg(
                      width: ParticipantListLayoutConstants.actionIconSize,
                      height: ParticipantListLayoutConstants.actionIconSize,
                      colorFilter: ColorFilter.mode(
                        context.colors.notificationSuccess,
                        BlendMode.srcIn,
                      ),
                    )
                  : context.images.iconVideoOff.svg(
                      width: ParticipantListLayoutConstants.actionIconSize,
                      height: ParticipantListLayoutConstants.actionIconSize,
                      colorFilter: ColorFilter.mode(
                        context.colors.signalDanger,
                        BlendMode.srcIn,
                      ),
                    ),
            ),
            const SizedBox(width: ParticipantListLayoutConstants.spacingMedium),
            if (_showMoreButton[p.name] == true)
              _buildActionButton(
                context,
                child: IconButtonWithActions(
                  padding: EdgeInsets.zero,
                  iconSize: ParticipantListLayoutConstants.actionIconSize,
                  icon: Icon(
                    Icons.more_vert_outlined,
                    color: context.colors.textNorm,
                    size: ParticipantListLayoutConstants.actionIconSize,
                  ),
                  offset: const Offset(-220, 0),
                  actions: p.participant is LocalParticipant
                      ? []
                      : [
                          if (p.participant != null) ...[
                            if (p
                                .participant!
                                .audioTrackPublications
                                .isNotEmpty)
                              OverlayActions(
                                title:
                                    p
                                        .participant!
                                        .audioTrackPublications
                                        .first
                                        .subscribed
                                    ? context.local.unsubscribe_audio
                                    : context.local.subscribe_audio,
                                icon: Icon(
                                  p
                                          .participant!
                                          .audioTrackPublications
                                          .first
                                          .subscribed
                                      ? Icons.mic_off
                                      : Icons.mic,
                                ),
                                onTap: () {
                                  widget.onTapParticipantAudioLocalAction?.call(
                                    p.participant,
                                  );
                                },
                              ),
                            if (p
                                .participant!
                                .videoTrackPublications
                                .isNotEmpty)
                              OverlayActions(
                                title:
                                    p
                                        .participant!
                                        .videoTrackPublications
                                        .first
                                        .subscribed
                                    ? context.local.unsubscribe_video
                                    : context.local.subscribe_video,
                                icon: Icon(
                                  p
                                          .participant!
                                          .videoTrackPublications
                                          .first
                                          .subscribed
                                      ? Icons.no_photography_rounded
                                      : Icons.camera_alt,
                                ),
                                onTap: () {
                                  widget.onTapParticipantVideoLocalAction.call(
                                    p.participant,
                                  );
                                },
                              ),
                            if (p
                                .participant!
                                .videoTrackPublications
                                .isNotEmpty)
                              OverlayActions(
                                title: context.local.remote_mute_video,
                                icon: Icon(
                                  Icons.close,
                                  color: context.colors.notificationError,
                                ),
                                onTap: () {
                                  widget.onTapParticipantVideoRemoteAction
                                      ?.call(p.participant);
                                },
                              ),
                            if (p
                                .participant!
                                .audioTrackPublications
                                .isNotEmpty)
                              OverlayActions(
                                title: context.local.remote_mute_audio,
                                icon: Icon(
                                  Icons.close,
                                  color: context.colors.notificationError,
                                ),
                                onTap: () {
                                  widget.onTapParticipantAudioRemoteAction
                                      ?.call(p.participant);
                                },
                              ),
                          ],
                          if (widget.isHost) ...[
                            OverlayActions(
                              title: context.local.force_mute,
                              icon: const Icon(Icons.mic_off),
                              onTap: () {
                                LocalToast.showToastification(
                                  context,
                                  'TODO',
                                  context.local.force_mute_participant(p.name),
                                );
                              },
                            ),
                            OverlayActions(
                              title: context.local.force_disable_camera,
                              icon: const Icon(Icons.no_photography_rounded),
                              onTap: () {
                                LocalToast.showToastification(
                                  context,
                                  'TODO',
                                  context.local
                                      .force_disable_camera_participant(p.name),
                                );
                              },
                            ),
                            OverlayActions(
                              title: context.local.kick_out,
                              icon: Icon(
                                Icons.close,
                                color: context.colors.notificationError,
                              ),
                              onTap: () {
                                LocalToast.showToastification(
                                  context,
                                  'TODO',
                                  context.local.kick_out_participant(p.name),
                                );
                              },
                            ),
                          ],
                        ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, {required Widget child}) {
    return Container(
      width: ParticipantListLayoutConstants.actionButtonSize,
      height: ParticipantListLayoutConstants.actionButtonSize,
      padding: const EdgeInsets.all(3),
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            ParticipantListLayoutConstants.spacingLarge,
          ),
        ),
      ),
      child: Center(child: child),
    );
  }
}

/// Composes the small status line under a participant's name. Web layers
/// these the same way: `Host · Recording`, with `Recording` only visible when
/// MeetMultipleRecording is enabled (the source data is gated upstream).
String _composeStatusLine({
  required bool isHost,
  required bool isRecording,
  required String recordingLabel,
}) {
  final parts = <String>[if (isHost) 'Host', if (isRecording) recordingLabel];
  return parts.join(' · ');
}

class WaitingRoomParticipantDetail {
  const WaitingRoomParticipantDetail({
    required this.id,
    required this.participantUid,
    required this.name,
    this.joinedAt,
  });

  /// Join request id from the server.
  final String id;

  /// Participant uid from the join request (used for reject API).
  final String participantUid;

  final String name;
  final DateTime? joinedAt;
}

class ParticipantDetail {
  final String name;
  final bool hasVideo;
  final bool hasAudio;
  final bool isHost;
  final bool isMe;
  final bool isRaisedHand;
  final bool isRecording;
  final Participant<TrackPublication<Track>>? participant;

  ParticipantDetail({
    required this.name,
    this.hasVideo = false,
    this.hasAudio = false,
    this.isHost = false,
    this.isMe = false,
    this.isRaisedHand = false,
    this.isRecording = false,
    this.participant,
  });
}
