import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

/// Figma-aligned rejoin pill (min height 60, 16 / 20 padding).
class FeedbackRejoinAction extends StatelessWidget {
  const FeedbackRejoinAction({required this.onRejoinMeeting, super.key});

  final VoidCallback onRejoinMeeting;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SizedBox(
            width: double.infinity,
            child: Material(
              color: Colors.white.withValues(alpha: 0.08),
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(200),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
              ),
              child: InkWell(
                onTap: onRejoinMeeting,
                borderRadius: BorderRadius.circular(200),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 20,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${context.local.left_by_mistake} ',
                                style: ProtonStyles.body2Medium(
                                  color: context.colors.textNorm,
                                ),
                              ),
                              TextSpan(
                                text: context.local.rejoin_meeting,
                                style: ProtonStyles.body2Medium(
                                  color: context.colors.interActionNormMajor1,
                                ),
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
