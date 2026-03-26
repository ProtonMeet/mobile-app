import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/alerts/base_bottom_sheet.dart';
import 'package:meet/views/components/button.v6.dart';

typedef OnLeaveMeeting = Future<void> Function();
typedef OnEndMeetingForAll = Future<void> Function();

Future<void> showLeaveRoomBottomSheet(
  BuildContext context, {
  required OnLeaveMeeting onLeaveMeeting,
  required OnEndMeetingForAll onEndMeetingForAll,
  required bool isHost,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.transparent,
    builder: (_) => LeaveRoomModal(
      onLeaveMeeting: onLeaveMeeting,
      onEndMeetingForAll: onEndMeetingForAll,
      isHost: isHost,
    ),
  );
}

class LeaveRoomModal extends StatelessWidget {
  const LeaveRoomModal({
    required this.onLeaveMeeting,
    required this.onEndMeetingForAll,
    required this.isHost,
    super.key,
  });

  final OnLeaveMeeting onLeaveMeeting;
  final OnEndMeetingForAll onEndMeetingForAll;
  final bool isHost;

  @override
  Widget build(BuildContext context) {
    final screenHeight = context.height;
    final availableHeight = screenHeight * 0.9;
    final contentHeight = isHost ? 440.0 : 360.0;
    final maxHeight = contentHeight > availableHeight
        ? availableHeight
        : contentHeight;

    return BaseBottomSheet(
      backgroundColor: context.colors.backgroundDark.withValues(alpha: 0.60),
      blurSigma: 14,
      maxHeight: maxHeight,
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      onBackdropTap: () {
        Navigator.of(context).maybePop();
      },
      child: Column(
        children: [
          _buildHandleBar(context),
          const SizedBox(height: 48),

          /// Title & subtitle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                Text(
                  context.local.leave_meeting,
                  textAlign: TextAlign.center,
                  style: ProtonStyles.headline(color: context.colors.textNorm),
                ),
                const SizedBox(height: 16),
                Text(
                  isHost
                      ? context.local.host_close_meeting_description
                      : context.local.close_meeting_description,
                  textAlign: TextAlign.center,
                  style: ProtonStyles.body2Medium(
                    color: context.colors.textWeak,
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),

          /// Action buttons
          LayoutBuilder(
            builder: (context, constraints) {
              final buttonWidth = constraints.maxWidth;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  /// End meeting for all
                  if (isHost) ...[
                    ButtonV6(
                      text: context.local.end_meeting_for_all,
                      width: buttonWidth,
                      height: 60,
                      radius: 200,
                      backgroundColor: context.colors.signalDangerMajor3,
                      textStyle: ProtonStyles.body1Semibold(
                        color: context.colors.textNorm,
                      ),
                      onPressed: onEndMeetingForAll,
                    ),
                    const SizedBox(height: 8),
                  ],

                  /// Leave meeting button
                  ButtonV6(
                    text: context.local.leave_meeting,
                    width: buttonWidth,
                    height: 60,
                    radius: 200,
                    backgroundColor: context.colors.signalDangerMajor3,
                    textStyle: ProtonStyles.body1Semibold(
                      color: context.colors.textNorm,
                    ),
                    onPressed: onLeaveMeeting,
                  ),
                  const SizedBox(height: 8),

                  /// Stay in meeting button
                  ButtonV6(
                    text: context.local.stay_in_meeting,
                    width: buttonWidth,
                    height: 60,
                    radius: 200,
                    backgroundColor: context.colors.interActionWeak,
                    textStyle: ProtonStyles.body1Semibold(
                      color: context.colors.textNorm,
                    ),
                    onPressed: () async {
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
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
