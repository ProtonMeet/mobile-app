// recording_top_banner.dart
//
// Always-on banner shown at the top of the meeting screen whenever *any*
// participant is recording. Driven entirely off [RoomState] — never opens or
// closes itself imperatively, so the source of truth remains the bloc.
//
// Wire-compatible with the web `RecordingTopBanner` UX:
//   • 1 recorder → "Recording in progress · Alice is recording"
//   • N recorders → "Recording in progress · Alice and N-1 others are recording"
//
// Hidden when MeetMultipleRecording is OFF and the recorder set is empty.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/rust/proton_meet/models/meet_participant.dart';
import 'package:meet/views/scenes/room/recording/recording_status_handler.dart';
import 'package:meet/views/scenes/room/room_bloc.dart';
import 'package:meet/views/scenes/room/room_state.dart';

class RecordingTopBanner extends StatelessWidget {
  const RecordingTopBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocSelector<
      RoomBloc,
      RoomState,
      ({List<String> recorders, Map<String, MeetParticipant> participants})
    >(
      selector: (state) => (
        recorders: state.participantsRecording,
        participants: state.frbParticipantsMap,
      ),
      builder: (context, data) {
        final recorders = data.recorders;
        if (recorders.isEmpty) {
          return const SizedBox.shrink();
        }

        final text = _buildText(context, recorders, data.participants);

        return Container(
          width: double.infinity,
          color: context.colors.recordingTopBanner,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: ProtonStyles.body2Medium(color: context.colors.textNorm),
              ),
            ),
          ),
        );
      },
    );
  }

  String _buildText(
    BuildContext context,
    List<String> recorders,
    Map<String, MeetParticipant> participants,
  ) {
    final namedRecorders = recorders
        .where((id) => id != kServerRecordingIdentity)
        .toList(growable: false);

    // Pure server recording (LiveKit egress only) — no participant identity to
    // show, fall back to the short banner.
    if (namedRecorders.isEmpty) {
      return context.local.recording_in_progress;
    }

    final firstName = _displayName(namedRecorders.first, participants);
    if (namedRecorders.length == 1) {
      return context.local.recording_in_progress_with_name(firstName);
    }
    final othersCount = namedRecorders.length - 1;
    return context.local.recording_in_progress_with_name_and_others(
      firstName,
      othersCount,
    );
  }

  String _displayName(
    String identity,
    Map<String, MeetParticipant> participants,
  ) {
    final p = participants[identity];
    if (p == null) return identity;
    final name = p.displayName;
    return (name?.isNotEmpty ?? false) ? name! : identity;
  }
}
