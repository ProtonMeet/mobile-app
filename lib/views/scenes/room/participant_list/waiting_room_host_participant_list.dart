import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/alerts/base_bottom_sheet_v2.dart';
import 'package:meet/views/components/bottom.sheets/bottom_sheet_handle_bar.dart';
import 'package:meet/views/scenes/room/get_participant_display_colors.dart';
import 'package:meet/views/scenes/room/room_bloc.dart';
import 'package:meet/views/scenes/room/room_event.dart';
import 'package:meet/views/scenes/room/room_state.dart';
import 'package:meet/views/scenes/room/room_state_exts.dart';
import 'package:meet/views/scenes/utils.dart';

import 'participant_list.dart';

enum _WaitingRoomParticipantTab { waitingRoom, allParticipants }

class WaitingRoomHostParticipantList extends StatefulWidget {
  const WaitingRoomHostParticipantList({
    required this.participants,
    required this.waitingParticipants,
    required this.onTapParticipantVideoLocalAction,
    this.onTapParticipantAudioLocalAction,
    this.onTapParticipantVideoRemoteAction,
    this.onTapParticipantAudioRemoteAction,
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
  State<WaitingRoomHostParticipantList> createState() =>
      _WaitingRoomHostParticipantListState();
}

class _WaitingRoomHostParticipantListState
    extends State<WaitingRoomHostParticipantList> {
  _WaitingRoomParticipantTab _selectedTab =
      _WaitingRoomParticipantTab.waitingRoom;

  final Map<String, ({Color backgroundColor, Color profileTextColor})>
  _colorCache = {};
  final Map<String, String> _initialsCache = {};

  @override
  void didUpdateWidget(WaitingRoomHostParticipantList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.waitingParticipants.length !=
            oldWidget.waitingParticipants.length ||
        widget.participants.length != oldWidget.participants.length) {
      _colorCache.clear();
      _initialsCache.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = context.isLandscape;

    final navBarHeight =
        ParticipantListLayoutConstants.headerHeight +
        ParticipantListLayoutConstants.tabBarHeight +
        (isLandscape
            ? ParticipantListLayoutConstants.spacingMedium
            : ParticipantListLayoutConstants.handleHeight);

    return BaseBottomSheetV2.withPinnedSliverScroll(
      isLandscape: isLandscape,
      blurSigma: 14,
      toolbarHeight: navBarHeight,
      innerEnableHandleDragPassthrough: false,
      flexibleSpaceChild: _buildPinnedHeader(context, isLandscape),
      slivers: _selectedTab == _WaitingRoomParticipantTab.waitingRoom
          ? _buildWaitingRoomSlivers(context)
          : [
              SliverFillRemaining(
                child: ParticipantListBody(
                  participants: widget.participants,
                  onTapParticipantVideoLocalAction:
                      widget.onTapParticipantVideoLocalAction,
                  onTapParticipantAudioLocalAction:
                      widget.onTapParticipantAudioLocalAction,
                  onTapParticipantVideoRemoteAction:
                      widget.onTapParticipantVideoRemoteAction,
                  onTapParticipantAudioRemoteAction:
                      widget.onTapParticipantAudioRemoteAction,
                  isHost: widget.isHost,
                  presentation: ParticipantListPresentation.embeddedScrollView,
                ),
              ),
            ],
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
          const SizedBox(height: ParticipantListLayoutConstants.spacingMedium),
        Padding(
          padding: const EdgeInsets.only(
            top: 12,
            bottom: 4,
            left: ParticipantListLayoutConstants.horizontalPadding,
            right: ParticipantListLayoutConstants.horizontalPadding,
          ),
          child: Text(
            context.local.show_participants_list,
            style: ProtonStyles.headline(
              fontSize: 18,
              color: context.colors.textNorm,
            ),
          ),
        ),
        _buildTabBar(context),
      ],
    );
  }

  Widget _buildTabBar(BuildContext context) {
    final waitingCount = widget.waitingParticipants.length;
    final allCount = widget.participants.length;

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 8,
        horizontal: defaultPadding,
      ),
      child: Row(
        children: [
          _ParticipantTabButton(
            label: context.local.participant_list_waiting_room_tab,
            count: waitingCount,
            selected: _selectedTab == _WaitingRoomParticipantTab.waitingRoom,
            onTap: () => setState(
              () => _selectedTab = _WaitingRoomParticipantTab.waitingRoom,
            ),
          ),
          const SizedBox(width: 8),
          _ParticipantTabButton(
            label: context.local.participant_list_all_participants_tab,
            count: allCount,
            selected:
                _selectedTab == _WaitingRoomParticipantTab.allParticipants,
            onTap: () => setState(
              () => _selectedTab = _WaitingRoomParticipantTab.allParticipants,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildWaitingRoomSlivers(BuildContext context) {
    final waitingParticipants = widget.waitingParticipants;

    return [
      if (waitingParticipants.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text(
              context.local.participant_list_no_waiting_participants,
              style: ProtonStyles.body2Medium(color: context.colors.textWeak),
              textAlign: TextAlign.center,
            ),
          ),
        )
      else
        SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final participant = waitingParticipants[index];
            return RepaintBoundary(
              key: ValueKey(participant.id),
              child:
                  BlocSelector<
                    RoomBloc,
                    RoomState,
                    ({
                      bool isAdmitLoading,
                      bool isRejectLoading,
                      bool admitAllInProgress,
                    })
                  >(
                    selector: (state) => (
                      isAdmitLoading: state.admittingWaitingRoomRequestIds
                          .contains(participant.id),
                      isRejectLoading: state.rejectingWaitingRoomRequestIds
                          .contains(participant.id),
                      admitAllInProgress: state.isAdmitAllWaitingRoomInProgress,
                    ),
                    builder: (context, loadingState) {
                      final actionsDisabled =
                          loadingState.isAdmitLoading ||
                          loadingState.isRejectLoading ||
                          loadingState.admitAllInProgress;

                      return _buildWaitingParticipantItem(
                        context,
                        participant,
                        isAdmitLoading: loadingState.isAdmitLoading,
                        isRejectLoading: loadingState.isRejectLoading,
                        actionsDisabled: actionsDisabled,
                      );
                    },
                  ),
            );
          }, childCount: waitingParticipants.length),
        ),
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            ParticipantListLayoutConstants.horizontalPadding,
            16,
            ParticipantListLayoutConstants.horizontalPadding,
            16 + MediaQuery.of(context).viewPadding.bottom,
          ),
          child:
              BlocSelector<
                RoomBloc,
                RoomState,
                ({bool isLoading, bool isDisabled})
              >(
                selector: (state) => (
                  isLoading: state.isAdmitAllWaitingRoomInProgress,
                  isDisabled:
                      state.isAdmitAllWaitingRoomInProgress ||
                      state.admittingWaitingRoomRequestIds.isNotEmpty ||
                      state.rejectingWaitingRoomRequestIds.isNotEmpty,
                ),
                builder: (context, admitAllState) {
                  final roomState = context.read<RoomBloc>().state;
                  final exceedsCapacity = roomState
                      .wouldAdmitAllExceedMeetingCapacity(
                        waitingParticipants.length,
                      );

                  return _AdmitAllButton(
                    onPressed: _onAdmitAll,
                    enabled:
                        waitingParticipants.isNotEmpty &&
                        !admitAllState.isDisabled &&
                        !exceedsCapacity,
                    isLoading: admitAllState.isLoading,
                  );
                },
              ),
        ),
      ),
    ];
  }

  Widget _buildWaitingParticipantItem(
    BuildContext context,
    WaitingRoomParticipantDetail participant, {
    required bool isAdmitLoading,
    required bool isRejectLoading,
    required bool actionsDisabled,
  }) {
    final colors = _colorCache.putIfAbsent(participant.id, () {
      final c = getParticipantDisplayColors(context, participant.id.hashCode);
      return (
        backgroundColor: c.backgroundColor,
        profileTextColor: c.profileTextColor,
      );
    });
    final initials = _initialsCache.putIfAbsent(
      participant.name,
      () => getInitials(participant.name),
    );
    final joinedAtLabel = participant.joinedAt == null
        ? null
        : context.local.participant_list_joined_at(
            context.formatLocalizedTime(participant.joinedAt!),
          );

    return Container(
      height: ParticipantListLayoutConstants.participantItemHeight,
      padding: const EdgeInsets.symmetric(
        horizontal: ParticipantListLayoutConstants.horizontalPadding,
        vertical: ParticipantListLayoutConstants.verticalPadding,
      ),
      child: Row(
        children: [
          _ParticipantAvatar(
            initials: initials,
            backgroundColor: colors.backgroundColor,
            textColor: colors.profileTextColor,
          ),
          const SizedBox(width: ParticipantListLayoutConstants.spacingLarge),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  participant.name,
                  style: ProtonStyles.body2Medium(
                    color: context.colors.textNorm,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (joinedAtLabel != null) ...[
                  Text(
                    joinedAtLabel,
                    style: ProtonStyles.body2Regular(
                      color: context.colors.textWeak,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          _WaitingRoomActionButton(
            icon: Icons.check_rounded,
            iconColor: context.colors.notificationSuccess,
            isLoading: isAdmitLoading,
            onPressed: actionsDisabled
                ? null
                : () => _onAdmitParticipant(participant),
          ),
          const SizedBox(width: ParticipantListLayoutConstants.spacingMedium),
          _WaitingRoomActionButton(
            icon: Icons.close_rounded,
            iconColor: context.colors.signalDanger,
            isLoading: isRejectLoading,
            onPressed: actionsDisabled
                ? null
                : () => _onDenyParticipant(participant),
          ),
        ],
      ),
    );
  }

  void _onAdmitParticipant(WaitingRoomParticipantDetail participant) {
    context.read<RoomBloc>().add(
      AdmitWaitingRoomJoinRequest(requestId: participant.id),
    );
  }

  void _onDenyParticipant(WaitingRoomParticipantDetail participant) {
    context.read<RoomBloc>().add(
      RejectWaitingRoomJoinRequest(
        requestId: participant.id,
        participantUid: participant.participantUid,
      ),
    );
  }

  void _onAdmitAll() {
    context.read<RoomBloc>().add(AdmitAllWaitingRoomJoinRequests());
  }
}

class _ParticipantTabButton extends StatelessWidget {
  const _ParticipantTabButton({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textColor = selected
        ? context.colors.textNorm
        : context.colors.textDisable;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: selected
                    ? ProtonStyles.body2Semibold(color: textColor)
                    : ProtonStyles.body2Medium(color: textColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(width: 6),
              _TabCountBadge(count: count, selected: selected),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabCountBadge extends StatelessWidget {
  const _TabCountBadge({required this.count, required this.selected});

  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: ShapeDecoration(
        color: selected ? Colors.white : context.colors.backgroundCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(200)),
      ),
      alignment: Alignment.center,
      child: Text(
        count.toString(),
        style: selected
            ? ProtonStyles.captionSemibold(color: context.colors.textInverted)
            : ProtonStyles.captionSemibold(color: context.colors.textDisable),
      ),
    );
  }
}

class _ParticipantAvatar extends StatelessWidget {
  const _ParticipantAvatar({
    required this.initials,
    required this.backgroundColor,
    required this.textColor,
  });

  final String initials;
  final Color backgroundColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: ParticipantListLayoutConstants.avatarSize,
      height: ParticipantListLayoutConstants.avatarSize,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: backgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              ParticipantListLayoutConstants.borderRadiusAvatar,
            ),
          ),
        ),
        child: Center(
          child: Text(
            initials,
            style: ProtonStyles.captionMedium(color: textColor),
          ),
        ),
      ),
    );
  }
}

class _WaitingRoomActionButton extends StatelessWidget {
  const _WaitingRoomActionButton({
    required this.icon,
    required this.iconColor,
    required this.onPressed,
    this.isLoading = false,
  });

  final IconData icon;
  final Color iconColor;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.04),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          ParticipantListLayoutConstants.spacingLarge,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isLoading ? null : onPressed,
        child: SizedBox(
          width: ParticipantListLayoutConstants.actionButtonSize,
          height: ParticipantListLayoutConstants.actionButtonSize,
          child: isLoading
              ? Center(
                  child: SizedBox(
                    width: ParticipantListLayoutConstants.actionIconSize,
                    height: ParticipantListLayoutConstants.actionIconSize,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        context.colors.textWeak,
                      ),
                    ),
                  ),
                )
              : Icon(
                  icon,
                  size: ParticipantListLayoutConstants.actionIconSize,
                  color: onPressed == null
                      ? iconColor.withValues(alpha: 0.4)
                      : iconColor,
                ),
        ),
      ),
    );
  }
}

class _AdmitAllButton extends StatelessWidget {
  const _AdmitAllButton({
    required this.onPressed,
    required this.enabled,
    this.isLoading = false,
  });

  final VoidCallback onPressed;
  final bool enabled;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final canPress = enabled && !isLoading;

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: canPress ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: context.colors.interActionWeak,
          disabledBackgroundColor: context.colors.interActionWeak.withValues(
            alpha: 0.5,
          ),
          foregroundColor: context.colors.textNorm,
          disabledForegroundColor: context.colors.textDisable,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    context.colors.textNorm,
                  ),
                ),
              )
            : Text(
                context.local.participant_list_admit_all,
                style: ProtonStyles.body1Medium(color: context.colors.textNorm),
              ),
      ),
    );
  }
}
