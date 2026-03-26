// room_tracks_handlers.dart
import 'dart:math';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/views/scenes/room/camera_layout.dart';
import 'package:meet/views/scenes/room/participant/participant_info.dart';

import 'room_bloc_participants.dart';
import 'room_event.dart';
import 'room_state.dart';

mixin RoomTracksHandlers
    on Bloc<RoomBlocEvent, RoomState>, RoomParticipantsHandlers {
  void registerTracksHandlers() {
    on<SortParticipants>(_onSortParticipants);
  }

  /// Sorts and organizes all participant tracks in the room.
  ///
  /// This method processes both remote and local participants, separating their tracks into:
  /// 1. **Screen share tracks** - Always set to HIGH quality at 30 FPS
  /// 2. **User media tracks** (video/audio) - Applies configurable quality and FPS settings
  ///
  /// **Sorting behavior for user media tracks (when count > 5):**
  /// - Primary: Last spoke time (descending). If both spoke within 60s, sorts by identity to prevent flickering
  /// - Secondary: Video availability (participants with video first)
  /// - Tertiary: Join time (ascending - earlier joins first)
  ///
  /// **Special handling:**
  /// - Includes participants without active video tracks for visibility in layouts
  /// - Local participant is inserted at the beginning (unless hideSelfCamera is true)
  /// - Calculates and updates speaker tracks
  /// - Manages screen sharing index bounds
  ///
  /// Emits updated state with sorted participant tracks, screen sharing tracks, and speaker tracks.
  Future<void> _onSortParticipants(
    SortParticipants event,
    Emitter<RoomState> emit,
  ) async {
    final room = state.room;
    final hideSelfCamera = state.hideSelfCamera;
    final List<ParticipantInfo> userMediaTracks = [];
    final List<ParticipantInfo> screenTracks = [];
    for (var participant in room.remoteParticipants.values) {
      bool hasVideo = false;
      for (var t in participant.videoTrackPublications) {
        hasVideo = true;
        if (t.isScreenShare) {
          /// ensure we have high quality for screen sharing
          t.setVideoQuality(VideoQuality.HIGH);
          t.setVideoFPS(30);
          final displayName = getParticipantDisplayName(participant);
          screenTracks.add(
            ParticipantInfo(
              displayName: getParticipantDisplayName(
                participant,
                isRemoteScreenShare: true,
              ),
              participant: participant,
              type: ParticipantTrackType.kScreenShare,
            ),
          );
          if (!userMediaTracks.any(
            (element) => element.participant.identity == participant.identity,
          )) {
            userMediaTracks.add(
              ParticipantInfo(
                displayName: displayName,
                participant: participant,
              ),
            );
          }
        } else {
          if (!userMediaTracks.any(
            (element) => element.participant.identity == participant.identity,
          )) {
            userMediaTracks.add(
              ParticipantInfo(
                displayName: getParticipantDisplayName(participant),
                participant: participant,
              ),
            );
          }
        }
      }
      if (!hasVideo) {
        /// add to userMediaTracks though remoteParticipant didn't publish video
        /// so we can see this user in camera layout
        ///
        if (!userMediaTracks.any(
          (element) => element.participant.identity == participant.identity,
        )) {
          userMediaTracks.add(
            ParticipantInfo(
              displayName: getParticipantDisplayName(participant),
              participant: participant,
            ),
          );
        }
      }
    }

    // remove the duplicates in userMediaTracks

    /// sort speakers for the grid if participant count > 5 (otherwise they can show in same page, so no need to sort them)
    /// 1st: last spokeAt desc (if user spoke in 60 seconds, they will order by identity instead of spokeAt to avoid screen flickering)
    /// 2ed: has video move up, no video move down
    /// 3rd: joinAt asc
    const sortCountCheck = 2;
    if (userMediaTracks.length > sortCountCheck) {
      sortUserMediaTracksBySpoken(userMediaTracks);
    }

    final localParticipantTracks =
        room.localParticipant?.videoTrackPublications;
    if (localParticipantTracks != null && localParticipantTracks.isNotEmpty) {
      for (var t in localParticipantTracks) {
        if (t.isScreenShare) {
          screenTracks.add(
            ParticipantInfo(
              participant: room.localParticipant!,
              type: ParticipantTrackType.kScreenShare,
              displayName: getParticipantDisplayName(
                room.localParticipant!,
                isLocalScreenShare: true,
              ),
            ),
          );
        } else {
          if (!hideSelfCamera) {
            userMediaTracks.insert(
              0,
              ParticipantInfo(
                displayName: getParticipantDisplayName(room.localParticipant!),
                participant: room.localParticipant!,
              ),
            );
          }
        }
      }
    } else if (room.localParticipant != null && !hideSelfCamera) {
      /// add to userMediaTracks though localParticipant didn't publish video
      /// so we can see this user in camera layout
      final displayName = getParticipantDisplayName(room.localParticipant!);
      userMediaTracks.insert(
        0,
        ParticipantInfo(
          displayName: displayName,
          participant: room.localParticipant!,
        ),
      );
    }
    final newParticipantTracks = [...userMediaTracks];
    final newSpeakerTracks = sortSpeakerTracks(
      findSpeakerTracks(userMediaTracks),
    );

    var screenSharingIndex = state.screenSharingIndex;
    if (screenTracks.isEmpty) {
      screenSharingIndex = 0;
    } else if (screenTracks.length - 1 < screenSharingIndex) {
      screenSharingIndex = max(0, screenTracks.length - 1);
    }

    // Calculate local and remote screen sharing status from actual tracks
    final isLocalScreenSharing = screenTracks.any(
      (track) => track.participant is LocalParticipant,
    );
    final isRemoteScreenSharing = screenTracks.any(
      (track) => track.participant is RemoteParticipant,
    );

    // Always use the actual track state, not the previous state
    // This ensures state stays in sync even if remote screen share stops local
    final finalIsLocalScreenSharing = isLocalScreenSharing;

    // If remote screen sharing just started and local is active, disable local screen sharing
    final wasRemoteScreenSharing = state.isRemoteScreenSharing;
    final wasLocalScreenSharing = state.isLocalScreenSharing;

    if (isRemoteScreenSharing &&
        !wasRemoteScreenSharing &&
        wasLocalScreenSharing) {
      // Remote screen sharing just started while local was active - disable local
      // Route through bloc handler so we also cleanup local screen share tracks
      add(ToggleScreenShare());
    }

    // Update camera enabled state for local participant
    final isCameraEnabled = room.localParticipant?.isCameraEnabled() ?? false;

    // Check if the participant tracks order has changed
    // Compare by participant identity to check if order is the same
    final oldTracks = state.participantTracks;
    bool hasOrderChanged = false;

    if (oldTracks.length != newParticipantTracks.length) {
      // Different length means order definitely changed
      hasOrderChanged = true;
    } else {
      // Check if participants are in the same order by comparing identities
      for (int i = 0; i < oldTracks.length; i++) {
        if (oldTracks[i].participant.identity !=
            newParticipantTracks[i].participant.identity) {
          hasOrderChanged = true;
          break;
        }

        if (oldTracks[i].displayName.toLowerCase() !=
            newParticipantTracks[i].displayName.toLowerCase()) {
          hasOrderChanged = true;
          break;
        }
      }
    }

    // Check if other track-related state has changed to minimize emissions
    final screenTracksChanged = !_listsEqual(
      state.screenSharingTracks,
      screenTracks,
    );
    final speakerTracksChanged = !_listsEqual(
      state.speakerTracks,
      newSpeakerTracks,
    );
    final screenSharingChanged =
        state.isLocalScreenSharing != finalIsLocalScreenSharing ||
        state.isRemoteScreenSharing != isRemoteScreenSharing ||
        state.screenSharingIndex != screenSharingIndex;
    final cameraEnabledChanged = state.isCameraEnabled != isCameraEnabled;

    // Only emit if something actually changed to reduce unnecessary rebuilds
    if (hasOrderChanged ||
        screenTracksChanged ||
        speakerTracksChanged ||
        screenSharingChanged ||
        cameraEnabledChanged) {
      emit(
        state.copyWith(
          participantTracks: hasOrderChanged
              ? newParticipantTracks
              : state.participantTracks,
          screenSharingTracks: screenTracksChanged
              ? screenTracks
              : state.screenSharingTracks,
          speakerTracks: speakerTracksChanged
              ? newSpeakerTracks
              : state.speakerTracks,
          isLocalScreenSharing: finalIsLocalScreenSharing,
          isRemoteScreenSharing: isRemoteScreenSharing,
          screenSharingIndex: screenSharingIndex,
          isCameraEnabled: isCameraEnabled,
          isTrackInitialized: true,
        ),
      );
    }
  }

  List<ParticipantInfo> sortSpeakerTracks(List<ParticipantInfo> speakers) {
    final layout = state.layout;
    if (layout != CameraLayout.mutliSpeaker) {
      return speakers;
    }

    /// only sort speaker for mutliSpeaker layout
    speakers.sort((a, b) {
      return a.participant.identity.compareTo(b.participant.identity) < 0
          ? -1
          : 1;
    });
    return speakers;
  }

  List<ParticipantInfo> findSpeakerTracks(
    List<ParticipantInfo> userMediaTracks,
  ) {
    final List<ParticipantInfo> speakers = [];
    for (final track in userMediaTracks) {
      final lastSpokeAt =
          track.participant.lastSpokeAt?.millisecondsSinceEpoch ?? 0.0;
      final current = DateTime.now().millisecondsSinceEpoch;

      /// identify recent speaker within 60s (60000ms)
      final isRecentSpeaker = (current - lastSpokeAt) <= 60000;
      if (track.participant.isSpeaking) {
        speakers.add(track);
      } else if (isRecentSpeaker) {
        speakers.add(track);
      }
    }
    return speakers.length > 4 ? speakers.take(4).toList() : speakers;
  }

  List<ParticipantInfo> getParticipantTracksWhenScreenSharing() {
    switch (state.layout) {
      case CameraLayout.grid:
      case CameraLayout.fixedSizing:
        return state.participantTracks;
      case CameraLayout.speaker:
        return state.speakerTracks.isNotEmpty
            ? state.speakerTracks.take(1).toList()
            : [];
      case CameraLayout.mutliSpeaker:
        return state.speakerTracks;
    }
  }

  List<ParticipantInfo> withoutSpeakerTracks(
    List<ParticipantInfo> userMediaTracks,
    List<ParticipantInfo> speakerTracks,
  ) {
    final List<String> speakerIdentities = speakerTracks
        .map((e) => e.participant.identity)
        .toList();
    return userMediaTracks
        .where((e) => !speakerIdentities.contains(e.participant.identity))
        .toList();
  }

  /// Sort speakers for the grid when there are many participants.
  /// Rules (applied in order):
  /// 1) Primary: raised hand (true first).
  /// 2) Secondary: lastSpokeAt DESC (most recent speakers first).
  ///    BUT: if both A and B spoke within the recent window, sort by identity to avoid jitter.
  /// 3) Tertiary: camera enabled (non-screen-share, unmuted) before camera off.
  /// 4) Final: joinedAt ASC (earlier joiners first).
  void sortUserMediaTracksBySpoken(List<ParticipantInfo> userMediaTracks) {
    const recentWindow = Duration(seconds: 10);
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    bool isRecent(DateTime? ts) =>
        ts != null &&
        (nowMs - ts.millisecondsSinceEpoch) <= recentWindow.inMilliseconds;

    int spokeMs(DateTime? ts) => ts?.millisecondsSinceEpoch ?? 0;

    userMediaTracks.sort((a, b) {
      final aP = a.participant;
      final bP = b.participant;
      final aRaised = state.raisedHandsByIdentity[aP.identity] == true;
      final bRaised = state.raisedHandsByIdentity[bP.identity] == true;

      // Raised hand gets the highest priority.
      if (aRaised != bRaised) {
        return aRaised ? -1 : 1;
      }

      final aLastMs = spokeMs(aP.lastSpokeAt);
      final bLastMs = spokeMs(bP.lastSpokeAt);

      final aRecent = isRecent(aP.lastSpokeAt);
      final bRecent = isRecent(bP.lastSpokeAt);

      // If both spoke recently, keep a stable order by identity to prevent UI flicker.
      if (aRecent && bRecent) {
        final idCmp = aP.identity.compareTo(bP.identity);
        if (idCmp != 0) return idCmp;
        // fall through to next criteria if identities are equal (extremely rare)
      } else if (aLastMs != bLastMs) {
        // Otherwise, order by lastSpokeAt DESC (0 means "never", so it naturally sinks)
        return bLastMs.compareTo(aLastMs);
      }

      // Camera ON before OFF (excludes screen share tracks, checks mute state)
      final aCam = aP.isCameraEnabled();
      final bCam = bP.isCameraEnabled();
      if (aCam != bCam) {
        return aCam ? -1 : 1;
      }

      // Earlier joiners first
      final joinCmp = aP.joinedAt.millisecondsSinceEpoch.compareTo(
        bP.joinedAt.millisecondsSinceEpoch,
      );
      if (joinCmp != 0) return joinCmp;

      // Final deterministic tiebreaker: identity
      return aP.identity.compareTo(bP.identity);
    });
  }

  /// Helper method to compare two lists of ParticipantInfo efficiently
  /// Returns true if lists are equal (same length and same participants in same order)
  bool _listsEqual(List<ParticipantInfo> a, List<ParticipantInfo> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].participant.identity != b[i].participant.identity ||
          a[i].displayName != b[i].displayName) {
        return false;
      }
    }
    return true;
  }
}
