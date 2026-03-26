import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/rust/proton_meet/models/upcoming_meeting.dart';
import 'package:meet/views/components/alerts/base_bottom_sheet.dart';
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
    isDismissible: true,
    builder: (context) => LayoutBuilder(
      builder: (context, _) {
        final maxHeight = context.height - 60;

        return BaseBottomSheet(
          backgroundColor: context.colors.backgroundDark.withValues(
            alpha: 0.60,
          ),
          blurSigma: 14,
          maxHeight: maxHeight,
          contentPadding: const EdgeInsets.only(bottom: 24),
          onBackdropTap: () {
            Navigator.of(context).maybePop();
          },
          child: SizedBox(
            height: maxHeight,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  _buildHandleBar(context),
                  const SizedBox(height: 24),
                  Expanded(
                    child: _LeftMeetingContent(
                      meetingLink: meetingLink,
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
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

Widget _buildHandleBar(BuildContext context) {
  return Container(
    width: 36,
    height: 4,
    decoration: BoxDecoration(
      color: context.colors.textWeak.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(100),
    ),
  );
}

class _LeftMeetingContent extends StatelessWidget {
  const _LeftMeetingContent({
    required this.meetingLink,
    required this.isHost,
    required this.isPaidUser,
    required this.isMeetMobileShowStartMeetingButtonEnabled,
    required this.showRejoin,
    this.title,
    this.content,
    required this.onRejoinMeeting,
    required this.onStartMeetingNow,
  });

  final FrbUpcomingMeeting meetingLink;
  final bool isHost;
  final bool isPaidUser;
  final bool isMeetMobileShowStartMeetingButtonEnabled;
  final bool showRejoin;
  final String? title;
  final String? content;
  final VoidCallback onRejoinMeeting;
  final VoidCallback onStartMeetingNow;

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

  bool get _showStartMeetingNowButton => !isPaidUser && !isHost && showRejoin;

  @override
  Widget build(BuildContext context) {
    final titleText = title ?? context.local.left_meeting_title;
    final contentText = content ?? _subtitleText(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 52),

        /// Icon
        Container(
          width: 64,
          height: 64,
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(),
          child: context.images.iconDoorModalHeader.svg(
            width: 64,
            height: 64,
            fit: BoxFit.fitWidth,
          ),
        ),
        const SizedBox(height: 52),

        /// Title + subtitle
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
        Expanded(child: Container()),

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
