import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';

/// “How was the call?” label + star row for the left-meeting summary sheet.
class FeedbackStarsFooter extends StatelessWidget {
  const FeedbackStarsFooter({
    required this.submitting,
    required this.rating,
    required this.onStarTap,
    super.key,
  });

  final bool submitting;
  final int? rating;
  final void Function(int starValue) onStarTap;

  static const double _footerHorizontalPadding = 24;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _footerHorizontalPadding,
        8,
        _footerHorizontalPadding,
        24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.local.call_quality_how_was,
            textAlign: TextAlign.center,
            style: ProtonStyles.body2Medium(color: context.colors.textWeak),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 28,
            child: submitting
                ? const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      final value = i + 1;
                      final r = rating;
                      final on = r != null && value <= r;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: InkWell(
                          onTap: () => onStarTap(value),
                          customBorder: const CircleBorder(),
                          child: on
                              ? context.images.iconFeedbackStar.svg24()
                              : context.images.iconFeedbackStarBorder.svg24(),
                        ),
                      );
                    }),
                  ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
