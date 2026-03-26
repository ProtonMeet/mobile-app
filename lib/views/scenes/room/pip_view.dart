import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/views/scenes/room/get_participant_display_colors.dart';
import 'package:meet/views/scenes/room/layout/responsive_camera_layout.dart';
import 'package:meet/views/scenes/room/participant/participant.dart';
import 'package:meet/views/scenes/room/participant/participant_info.dart';
import 'package:meet/views/scenes/room/room_bloc.dart';
import 'package:meet/views/scenes/room/room_state.dart';

/// PIP view widget that displays meeting content in Picture-in-Picture mode
class PipView extends StatelessWidget {
  final Room room;
  final bool isScreenSharing;

  const PipView({required this.room, super.key, this.isScreenSharing = false});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RoomBloc, RoomState>(
      builder: (context, state) {
        if (isScreenSharing) {
          return _buildScreenSharingView(context, state);
        }
        return _buildCameraView(context, state);
      },
    );
  }

  Widget _buildScreenSharingView(BuildContext context, RoomState state) {
    return Scaffold(
      backgroundColor: Colors.black,
      body:
          BlocSelector<
            RoomBloc,
            RoomState,
            (int index, List<ParticipantInfo> tracks)
          >(
            selector: (state) {
              return (state.screenSharingIndex, state.screenSharingTracks);
            },
            builder: (context, data) {
              final tracks = data.$2;
              final index = data.$1;

              if (tracks.isEmpty) {
                return const SizedBox.shrink();
              }

              final safeIndex = index < tracks.length
                  ? index
                  : tracks.length - 1;

              return InteractiveViewer(
                minScale: 0.5,
                maxScale: 5.0,
                child: ParticipantWidget.widgetFor(
                  MediaQuery.of(context).size.width,
                  MediaQuery.of(context).size.height,
                  getParticipantDisplayColors(context, safeIndex),
                  tracks[safeIndex],
                  showStatsLayer: false,
                  roundedBorder: false,
                ),
              );
            },
          ),
    );
  }

  Widget _buildCameraView(BuildContext context, RoomState state) {
    return Scaffold(
      backgroundColor: Colors.black,
      body:
          BlocSelector<
            RoomBloc,
            RoomState,
            (
              List<ParticipantInfo> participantTracks,
              List<ParticipantInfo> speakerTracks,
            )
          >(
            selector: (state) => (state.participantTracks, state.speakerTracks),
            builder: (context, data) {
              return _buildCameraLayout(context, data.$1, data.$2);
            },
          ),
    );
  }

  Widget _buildCameraLayout(
    BuildContext context,
    List<ParticipantInfo> participantTracks,
    List<ParticipantInfo> speakerTracks,
  ) {
    // For PIP mode, show a simple grid layout
    if (participantTracks.isEmpty) {
      return const Center(
        child: Text('No participants', style: TextStyle(color: Colors.white)),
      );
    }

    // Show first participant in PIP mode (simple single view)
    return ResponsiveCameraLayout(
      participantTracks: participantTracks,
      room: room,
      hideNavigationIcons: true,
    );
  }
}
