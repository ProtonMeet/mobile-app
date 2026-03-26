import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';

class StartActionText extends StatelessWidget {
  const StartActionText({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        context.images.iconAdd.svg20(),
        const SizedBox(width: 10),
        Text(
          context.local.create_meeting_button,
          style: ProtonStyles.body1Semibold(color: context.colors.protonBlue),
        ),
      ],
    );
  }
}

class StartActionTextLong extends StatelessWidget {
  const StartActionTextLong({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      context.local.start_an_instant_meeting,
      style: ProtonStyles.body1Medium(color: context.colors.protonBlue),
    );
  }
}
