import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';

/// Pre-rating sheet hero: logo, title, and subtitle.
class PreRatingSheetHero extends StatelessWidget {
  const PreRatingSheetHero({
    required this.title,
    required this.subtitle,
    super.key,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          context.images.iconLeaveMeetingGuest.svg64(),
          const SizedBox(height: 40),
          Align(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: ProtonStyles.headline(color: context.colors.textNorm),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: ProtonStyles.body2Medium(
                    color: context.colors.textWeak,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
