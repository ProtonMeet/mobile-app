import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/rust/proton_meet/models/upcoming_meeting.dart';
import 'package:meet/views/components/alerts/base_bottom_sheet_v2.dart';
import 'package:meet/views/components/gradient_action_button.dart';

typedef OnRejoinMeeting = void Function();
typedef OnStartMeetingNow = void Function();

Future<void> showLeftMeetingBottomSheet(
  BuildContext context, {
  required FrbUpcomingMeeting meetingLink,
  required OnRejoinMeeting onRejoinMeeting,
  required OnStartMeetingNow onStartMeetingNow,
  required bool isHost,
  required bool isPaidUser,
  required bool isMeetMobileShowStartMeetingButtonEnabled,
  bool showRejoin = true,
  String? title,
  String? content,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.transparent,
    builder: (context) => LayoutBuilder(
      builder: (context, _) {
        final isLandscape = context.isLandscape;
        final maxHeight = isLandscape
            ? context.height - 20
            : context.height - 160;

        return _LeftMeetingSheetModalBody(
          key: ValueKey(meetingLink.id),
          maxHeight: maxHeight,
          onBackdropTap: () => Navigator.of(context).maybePop(),
          isHost: isHost,
          isPaidUser: isPaidUser,
          isMeetMobileShowStartMeetingButtonEnabled:
              isMeetMobileShowStartMeetingButtonEnabled,
          showRejoin: showRejoin,
          title: title,
          content: content,
          onRejoinMeeting: () {
            Navigator.of(context).pop();
            onRejoinMeeting();
          },
          onStartMeetingNow: () {
            Navigator.of(context).pop();
            onStartMeetingNow();
          },
        );
      },
    ),
  );
}

class _LeftMeetingSheetModalBody extends StatelessWidget {
  const _LeftMeetingSheetModalBody({
    required this.maxHeight,
    required this.onBackdropTap,
    required this.isHost,
    required this.isPaidUser,
    required this.isMeetMobileShowStartMeetingButtonEnabled,
    required this.showRejoin,
    required this.onRejoinMeeting,
    required this.onStartMeetingNow,
    this.title,
    this.content,
    super.key,
  });

  final double maxHeight;
  final VoidCallback onBackdropTap;
  final bool isHost;
  final bool isPaidUser;
  final bool isMeetMobileShowStartMeetingButtonEnabled;
  final bool showRejoin;
  final String? title;
  final String? content;
  final VoidCallback onRejoinMeeting;
  final VoidCallback onStartMeetingNow;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isLandscape = mediaQuery.size.width > mediaQuery.size.height;

    return BaseBottomSheetV2.withPinnedSliverScroll(
      isLandscape: isLandscape,
      modalOnBackdropTap: onBackdropTap,
      modalMaxHeight: maxHeight,
      innerEnableHandleDragPassthrough: false,
      outerEnableHandleDragPassthrough: true,
      blurSigma: 14,
      borderSideAlpha: 0.04,
      sheetBackgroundColor: context.colors.backgroundDark.withValues(
        alpha: 0.60,
      ),
      slivers: [
        SliverToBoxAdapter(
          child: _LeftMeetingUpperContent(
            isHost: isHost,
            isPaidUser: isPaidUser,
            isLandscape: isLandscape,
            title: title,
            content: content,
          ),
        ),
        SliverFillRemaining(
          hasScrollBody: false,
          child: SafeArea(
            child: _LeftMeetingLowerActions(
              isHost: isHost,
              isPaidUser: isPaidUser,
              isMeetMobileShowStartMeetingButtonEnabled:
                  isMeetMobileShowStartMeetingButtonEnabled,
              showRejoin: showRejoin,
              onRejoinMeeting: onRejoinMeeting,
              onStartMeetingNow: onStartMeetingNow,
            ),
          ),
        ),
      ],
    );
  }
}

class _LeftMeetingUpperContent extends StatelessWidget {
  const _LeftMeetingUpperContent({
    required this.isHost,
    required this.isPaidUser,
    required this.isLandscape,
    this.title,
    this.content,
  });

  final bool isHost;
  final bool isPaidUser;
  final String? title;
  final String? content;
  final bool isLandscape;

  String _subtitleText(BuildContext context) {
    if (!isPaidUser && !isHost) {
      return context.local.left_meeting_subtitle_guest_free;
    }
    if (isPaidUser && !isHost) {
      return context.local.left_meeting_subtitle_guest_paid;
    }
    if (!isPaidUser && isHost) {
      return context.local.left_meeting_subtitle_host_free;
    }
    return context.local.left_meeting_subtitle_host_paid;
  }

  @override
  Widget build(BuildContext context) {
    final titleText = title ?? context.local.left_meeting_title;
    final contentText = content ?? _subtitleText(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isLandscape) const SizedBox(height: 24),
        const SizedBox(height: 52),
        Container(
          width: 64,
          height: 64,
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(),
          child: context.images.iconDoorModalHeader.svg64(),
        ),
        const SizedBox(height: 52),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              Text(
                titleText,
                textAlign: TextAlign.center,
                style: ProtonStyles.headline(color: context.colors.textNorm),
              ),
              const SizedBox(height: 12),
              Text(
                contentText,
                textAlign: TextAlign.center,
                style: ProtonStyles.bodySmallSemibold(
                  color: context.colors.textWeak,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LeftMeetingLowerActions extends StatelessWidget {
  const _LeftMeetingLowerActions({
    required this.isHost,
    required this.isPaidUser,
    required this.isMeetMobileShowStartMeetingButtonEnabled,
    required this.showRejoin,
    required this.onRejoinMeeting,
    required this.onStartMeetingNow,
  });

  final bool isHost;
  final bool isPaidUser;
  final bool isMeetMobileShowStartMeetingButtonEnabled;
  final bool showRejoin;
  final VoidCallback onRejoinMeeting;
  final VoidCallback onStartMeetingNow;

  bool get _showStartMeetingNowButton => !isPaidUser && !isHost && showRejoin;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Spacer(),
        if (_showStartMeetingNowButton &&
            isMeetMobileShowStartMeetingButtonEnabled) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
            child: SizedBox(
              width: double.infinity,
              height: 60,
              child: GradientActionButton(
                text: context.local.start_meeting_now,
                textStyle: ProtonStyles.body1Medium(
                  color: context.colors.textInverted,
                ),
                onPressed: onStartMeetingNow,
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
        if (showRejoin)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
            child: Align(
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    context.local.left_by_mistake,
                    style: ProtonStyles.body1Medium(
                      color: context.colors.textNorm,
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: onRejoinMeeting,
                    child: Text(
                      context.local.rejoin_meeting,
                      style: ProtonStyles.body1Medium(
                        color: context.colors.protonBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 52),
      ],
    );
  }
}
