import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/helper/logger.dart' as l;

import 'room_event.dart';
import 'room_state.dart';

/// Debug / diagnostics helpers for RoomBloc.
///
/// Kept in a separate file to keep `room_bloc.dart` focused on behavior.
mixin RoomBlocDebugLogging on Bloc<RoomBlocEvent, RoomState> {
  int countRemoteSubscribedVideoPubs(Room room) {
    var count = 0;
    for (final rp in room.remoteParticipants.values) {
      for (final pub in rp.videoTrackPublications) {
        if (pub.subscribed) count++;
      }
    }
    return count;
  }

  int countRemoteSubscribedScreenShareVideoPubs(Room room) {
    var count = 0;
    for (final rp in room.remoteParticipants.values) {
      for (final pub in rp.videoTrackPublications) {
        if (pub.subscribed && pub.isScreenShare) count++;
      }
    }
    return count;
  }

  void logRoomTrackStats(String tag, Room room) {
    final lp = room.localParticipant;
    final localPubs = lp?.trackPublications.values.length ?? 0;
    final localScreenPubs = lp == null
        ? 0
        : lp.trackPublications.values
              .whereType<LocalTrackPublication>()
              .where((p) => p.isScreenShare)
              .length;
    final remoteSubscribedVideo = countRemoteSubscribedVideoPubs(room);
    final remoteSubscribedScreenShare =
        countRemoteSubscribedScreenShareVideoPubs(room);
    l.logger.d(
      '[RoomBloc][$tag] localPubs=$localPubs localScreenPubs=$localScreenPubs '
      'remoteSubscribedVideo=$remoteSubscribedVideo '
      'remoteSubscribedScreenShare=$remoteSubscribedScreenShare',
    );
  }
}
