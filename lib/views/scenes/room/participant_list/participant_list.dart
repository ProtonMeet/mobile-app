import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/local_toast.dart';

import 'package:meet/rust/proton_meet/models/meeting_info.dart';
import 'package:meet/views/components/alerts/base_bottom_sheet_v2.dart';
import 'package:meet/views/components/bottom.sheets/bottom_sheet_handle_bar.dart';
import 'package:meet/views/scenes/room/get_participant_display_colors.dart';
import 'package:meet/views/scenes/room/room_bloc.dart';
import 'package:meet/views/scenes/room/room_state.dart';
import 'package:meet/views/scenes/utils.dart';
import 'package:meet/views/scenes/widgets/icon.button.with.actions.dart';

class ParticipantList extends StatefulWidget {
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

  const ParticipantList({
    required this.participants,
    required this.onTapParticipantVideoLocalAction,
    this.onTapParticipantAudioLocalAction,
    this.onTapParticipantVideoRemoteAction,
    this.onTapParticipantAudioRemoteAction,
    this.isHost = false,
    super.key,
  });

  @override
  State<ParticipantList> createState() => _ParticipantListState();
}

class _ParticipantListConstants {
  static const double headerHeight = 52.0;
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

class _ParticipantListState extends State<ParticipantList> {
  final Map<String, bool> _showMoreButton = {};
  final Map<String, ({Color backgroundColor, Color profileTextColor})>
  _colorCache = {};
  final Map<String, String> _initialsCache = {};

  List<ParticipantDetail> get _filteredParticipants => widget.participants;

  @override
  void didUpdateWidget(ParticipantList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.participants.length != oldWidget.participants.length) {
      _colorCache.clear();
      _initialsCache.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    final isLandscape = screenWidth > screenHeight;

    final navBarHeight =
        _ParticipantListConstants.headerHeight +
        (isLandscape
            ? _ParticipantListConstants.spacingMedium
            : _ParticipantListConstants.handleHeight);

    return BaseBottomSheetV2.withPinnedSliverScroll(
      isLandscape: isLandscape,
      blurSigma: 14,
      toolbarHeight: navBarHeight,
      flexibleSpaceChild: _buildPinnedHeader(context, isLandscape),
      slivers: _buildSlivers(context),
    );
  }

  Widget _buildPinnedHeader(BuildContext context, bool isLandscape) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isLandscape)
          const BottomSheetHandleBar()
        else
          const SizedBox(height: _ParticipantListConstants.spacingMedium),
        _buildHeader(context),
      ],
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
              margin: const EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: 16,
              ),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(24),
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
              final key =
                  participant.participant?.identity ?? participant.name;
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
    ];
  }

  bool _isGuestMeetingRoom(FrbMeetingInfo? meetingInfo) {
    return (meetingInfo?.maxParticipants ?? 4) <= 4;
  }

  Widget _buildHeader(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        width: double.infinity,
        height: _ParticipantListConstants.headerHeight,
        padding: const EdgeInsets.only(
          top: 12.0,
          bottom: 4.0,
          left: _ParticipantListConstants.horizontalPadding,
          right: _ParticipantListConstants.horizontalPadding,
        ),
        decoration: const ShapeDecoration(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(
                _ParticipantListConstants.borderRadiusMedium,
              ),
              topRight: Radius.circular(
                _ParticipantListConstants.borderRadiusMedium,
              ),
            ),
          ),
        ),
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
            const SizedBox(width: _ParticipantListConstants.spacingSmall),
            BlocSelector<RoomBloc, RoomState, (FrbMeetingInfo?, bool)>(
              selector: (state) => (state.meetingInfo, state.isHost),
              builder: (context, data) {
                final meetingInfo = data.$1;
                // From design, we only show the max participants count if the user is the host
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
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 48, color: context.colors.textHint),
          const SizedBox(height: _ParticipantListConstants.spacingLarge),
          Text(
            context.local.no_participants_found,
            style: ProtonStyles.body1Medium(color: context.colors.textHint),
          ),
          const SizedBox(height: _ParticipantListConstants.spacingMedium),
          Text(
            context.local.try_different_search_term,
            style: ProtonStyles.body2Regular(color: context.colors.textWeak),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantItem(BuildContext context, ParticipantDetail p) {
    // Cache colors and initials to avoid recalculating on every build
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
        height: _ParticipantListConstants.participantItemHeight,
        padding: const EdgeInsets.only(
          top: _ParticipantListConstants.verticalPadding,
          left: _ParticipantListConstants.horizontalPadding,
          right: _ParticipantListConstants.spacingSmall,
          bottom: _ParticipantListConstants.verticalPadding,
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: _ParticipantListConstants.avatarSize,
                    height: _ParticipantListConstants.avatarSize,
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: ShapeDecoration(
                        color: colors.backgroundColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            _ParticipantListConstants.borderRadiusAvatar,
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
                  const SizedBox(width: _ParticipantListConstants.spacingLarge),
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
                        if (p.isHost)
                          Text(
                            'Meeting host',
                            style: ProtonStyles.body2Regular(
                              color: context.colors.textWeak,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: _ParticipantListConstants.spacingMedium),
            _buildActionButton(
              context,
              child: p.hasAudio
                  ? context.images.iconAudioOnWave.svg(
                      width: _ParticipantListConstants.actionIconSize,
                      height: _ParticipantListConstants.actionIconSize,
                      colorFilter: ColorFilter.mode(
                        context.colors.notificationSuccess,
                        BlendMode.srcIn,
                      ),
                    )
                  : context.images.iconAudioOff.svg(
                      width: _ParticipantListConstants.actionIconSize,
                      height: _ParticipantListConstants.actionIconSize,
                      colorFilter: ColorFilter.mode(
                        context.colors.signalDanger,
                        BlendMode.srcIn,
                      ),
                    ),
            ),
            const SizedBox(width: _ParticipantListConstants.spacingMedium),
            _buildActionButton(
              context,
              child: p.hasVideo
                  ? context.images.iconVideoOn.svg(
                      width: _ParticipantListConstants.actionIconSize,
                      height: _ParticipantListConstants.actionIconSize,
                      colorFilter: ColorFilter.mode(
                        context.colors.notificationSuccess,
                        BlendMode.srcIn,
                      ),
                    )
                  : context.images.iconVideoOff.svg(
                      width: _ParticipantListConstants.actionIconSize,
                      height: _ParticipantListConstants.actionIconSize,
                      colorFilter: ColorFilter.mode(
                        context.colors.signalDanger,
                        BlendMode.srcIn,
                      ),
                    ),
            ),
            const SizedBox(width: _ParticipantListConstants.spacingMedium),
            if (_showMoreButton[p.name] == true)
              _buildActionButton(
                context,
                child: IconButtonWithActions(
                  padding: EdgeInsets.zero,
                  iconSize: _ParticipantListConstants.actionIconSize,
                  icon: Icon(
                    Icons.more_vert_outlined,
                    color: context.colors.textNorm,
                    size: _ParticipantListConstants.actionIconSize,
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
      width: _ParticipantListConstants.actionButtonSize,
      height: _ParticipantListConstants.actionButtonSize,
      padding: const EdgeInsets.all(3),
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            _ParticipantListConstants.spacingLarge,
          ),
        ),
      ),
      child: Center(child: child),
    );
  }
}

class ParticipantDetail {
  final String name;
  final bool hasVideo;
  final bool hasAudio;
  final bool isHost;
  final bool isMe;
  final bool isRaisedHand;
  final Participant<TrackPublication<Track>>? participant;

  ParticipantDetail({
    required this.name,
    this.hasVideo = false,
    this.hasAudio = false,
    this.isHost = false,
    this.isMe = false,
    this.isRaisedHand = false,
    this.participant,
  });
}
