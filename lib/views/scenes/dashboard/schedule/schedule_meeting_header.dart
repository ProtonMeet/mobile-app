import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/views/scenes/room/get_participant_display_colors.dart';

class ScheduleMeetingHeader extends StatelessWidget {
  const ScheduleMeetingHeader({required this.displayColors, super.key});

  final ParticipantDisplayColors? displayColors;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child:
              displayColors?.meetingLogo?.svg56() ??
              context.images.iconScheduleLogo.svg56(),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            context.local.schedule_a_meeting,
            textAlign: TextAlign.center,
            style: ProtonStyles.headline(
              color: context.colors.textNorm,
              fontSize: 24,
            ),
          ),
        ),
      ],
    );
  }
}
