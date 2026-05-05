import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

/// Primary and secondary actions (positive + negative).
class PreRatingSheetActions extends StatelessWidget {
  const PreRatingSheetActions({
    required this.positiveLabel,
    required this.negativeLabel,
    required this.onPositiveAction,
    required this.onNegativeAction,
    super.key,
  });

  final String positiveLabel;
  final String negativeLabel;
  final VoidCallback onPositiveAction;
  final VoidCallback onNegativeAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          /// Positive action
          Material(
            color: context.colors.clear,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onPositiveAction,
              child: Ink(
                height: 64,
                padding: const EdgeInsets.all(16),
                decoration: ShapeDecoration(
                  color: context.colors.interActionNormMajor1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      positiveLabel,
                      style: ProtonStyles.body1Semibold(
                        color: context.colors.textInverted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          /// Negative action
          Material(
            color: context.colors.clear,
            child: InkWell(
              borderRadius: BorderRadius.circular(200),
              onTap: onNegativeAction,
              child: Ink(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
                decoration: ShapeDecoration(
                  color: context.colors.white.withValues(alpha: 0.08),
                  shape: RoundedRectangleBorder(
                    side: BorderSide(
                      color: context.colors.white.withValues(alpha: 0.04),
                    ),
                    borderRadius: BorderRadius.circular(200),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      negativeLabel,
                      style: ProtonStyles.body1Semibold(
                        color: context.colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
