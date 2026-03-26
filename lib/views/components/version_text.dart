import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

class VersionText extends StatelessWidget {
  const VersionText({required this.versionDisplay, super.key});

  final String versionDisplay;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Text(
        context.local.version(versionDisplay),
        textAlign: TextAlign.center,
        style: ProtonStyles.captionMedium(color: context.colors.textHint),
      ),
    );
  }
}
