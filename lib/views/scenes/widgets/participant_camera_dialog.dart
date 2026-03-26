import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/scenes/room/get_participant_display_colors.dart';
import 'package:meet/views/scenes/room/participant/participant.dart';
import 'package:meet/views/scenes/room/participant/participant_info.dart';

class ParticipantCameraDialog extends StatelessWidget {
  final ParticipantInfo participantTrack;

  const ParticipantCameraDialog({required this.participantTrack, super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Stack(
        children: [
          SizedBox(
            width: context.width,
            height: context.height,
            child: ParticipantWidget.widgetFor(
              context.width,
              context.height,
              getParticipantDisplayColors(context, 0),
              participantTrack,
              showStatsLayer: false,
            ),
          ),
          Positioned(
            right: 20,
            top: 20,
            child: CircleAvatar(
              radius: 20,
              backgroundColor: context.colors.backgroundSecondary,
              child: IconButton(
                color: context.colors.textNorm,
                icon: const Icon(Icons.close),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  static void show(BuildContext context, ParticipantInfo participantTrack) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return ParticipantCameraDialog(participantTrack: participantTrack);
      },
    );
  }
}
