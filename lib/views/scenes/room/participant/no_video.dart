import 'package:flutter/material.dart';

import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/scenes/room/get_participant_display_colors.dart';
import 'package:meet/views/scenes/utils.dart';

class NoVideoWidget extends StatelessWidget {
  final String name;
  final ParticipantDisplayColors displayColors;

  const NoVideoWidget({
    required this.name,
    required this.displayColors,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final initials = getInitials(name);
    final bgColor = displayColors.backgroundColor;
    final textColor = displayColors.profileTextColor;

    return Container(
      alignment: Alignment.center,
      color: bgColor,
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final size = 80.0;
          return CircleAvatar(
            radius: size / 2,
            backgroundColor: textColor,
            child: Text(
              initials,
              style: ProtonStyles.headline(
                fontVariation: 500,
                color: context.colors.textInverted,
              ),
            ),
          );
        },
      ),
    );
  }
}
