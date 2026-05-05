import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/views/components/gradient_action_button.dart';
import 'package:meet/views/scenes/feedbacks/feedback_rejoin_action.dart';
import 'package:meet/views/scenes/feedbacks/feedback_stars_footer.dart';

/// Summary step (door, copy, rejoin / start) + optional star rating footer.
List<Widget> buildLeftMeetingSummarySlivers({
  required BuildContext context,
  required bool isKickedOut,
  required String titleText,
  required String contentText,
  required bool showStartMeetingButton,
  required bool showRejoin,
  required VoidCallback onStartMeetingNow,
  required VoidCallback onRejoinMeeting,
  required bool feedbackEnabled,
  required bool submitting,
  required int? rating,
  required void Function(int starValue) onStarTap,
}) {
  return [
    SliverFillRemaining(
      hasScrollBody: false,
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  context.images.iconDoorModalHeader.svg64(),
                  const SizedBox(height: 40),
                  Text(
                    titleText,
                    textAlign: TextAlign.center,
                    style: ProtonStyles.headline(
                      color: context.colors.textNorm,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      contentText,
                      textAlign: TextAlign.center,
                      style: ProtonStyles.bodySmallSemibold(
                        color: context.colors.textWeak,
                      ),
                    ),
                  ),
                  if (showStartMeetingButton) ...[
                    const SizedBox(height: 40),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: SizedBox(
                        height: 60,
                        width: double.infinity,
                        child: GradientActionButton(
                          text: context.local.start_meeting_now,
                          textStyle: ProtonStyles.body1Medium(
                            color: context.colors.textInverted,
                          ),
                          onPressed: onStartMeetingNow,
                        ),
                      ),
                    ),
                  ],
                  if (showRejoin) ...[
                    showStartMeetingButton
                        ? const SizedBox(height: 8)
                        : const SizedBox(height: 40),
                    FeedbackRejoinAction(onRejoinMeeting: onRejoinMeeting),
                  ],
                ],
              ),
            ),
            if (feedbackEnabled && !isKickedOut) ...[
              SizedBox(
                height: context.height > 800
                    ? 80
                    : (showRejoin && showStartMeetingButton)
                    ? 32
                    : 8,
              ),
              FeedbackStarsFooter(
                submitting: submitting,
                rating: rating,
                onStarTap: onStarTap,
              ),
            ],
          ],
        ),
      ),
    ),
  ];
}
