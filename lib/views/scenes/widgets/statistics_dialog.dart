import 'dart:math';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/scenes/room/participant/participant_stats.dart';

class StatisticsDialog extends StatelessWidget {
  final Participant? participant;
  final List<Participant>? participants;
  final bool showAllParticipants;

  const StatisticsDialog({
    super.key,
    this.participant,
    this.participants,
    this.showAllParticipants = false,
  }) : assert(
         (participant != null && !showAllParticipants) ||
             (participants != null && showAllParticipants),
         'Either provide a single participant or a list of participants with showAllParticipants=true',
       );

  @override
  Widget build(BuildContext context) {
    if (showAllParticipants) {
      return _buildAllParticipantsStats(context);
    } else {
      return _buildSingleParticipantStats(context);
    }
  }

  Widget _buildSingleParticipantStats(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        width: min(MediaQuery.of(context).size.width * 0.9, 800),
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ),
            Expanded(child: ParticipantStatsWidget(participant: participant!)),
          ],
        ),
      ),
    );
  }

  Widget _buildAllParticipantsStats(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        width: min(MediaQuery.of(context).size.width * 0.9, 800),
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Video Stats - All Participants',
                  style: ProtonStyles.subheadline(
                    color: context.colors.textNorm,
                    fontSize: 16,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: participants!.length,
                itemBuilder: (context, index) {
                  final participant = participants![index];
                  final isLocal = participant is LocalParticipant;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text(
                              '${participant.name} ${isLocal ? "(You)" : ""}',
                              style: ProtonStyles.body1Medium(
                                color: context.colors.textNorm,
                              ),
                            ),
                          ),
                          ParticipantStatsWidget(participant: participant),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void showSingleParticipantStats(
    BuildContext context,
    Participant participant,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatisticsDialog(participant: participant);
      },
    );
  }

  static void showAllParticipantsStats(
    BuildContext context,
    List<Participant> participants,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatisticsDialog(
          participants: participants,
          showAllParticipants: true,
        );
      },
    );
  }
}
