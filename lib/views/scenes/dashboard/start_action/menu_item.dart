import 'package:flutter/material.dart';
import 'package:meet/constants/assets.gen.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';

class MenuItem extends StatelessWidget {
  const MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final SvgGenImage icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            icon.svg24(color: context.colors.interActionNorm),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: ProtonStyles.body1Medium(
                  color: context.colors.interActionNorm,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
