// room_tracks_handlers.dart
import 'dart:async';
import 'dart:math';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/views/scenes/room/active_speaker_order.dart';
import 'package:meet/views/scenes/room/camera_layout.dart';
import 'package:meet/views/scenes/room/participant/participant_info.dart';

import 'room_bloc_participants.dart';
import 'room_bloc_pip.dart';
import 'room_event.dart';
import 'room_event_bridge.dart';
import 'room_state.dart';

mixin RoomTracksHandlers
    on
        Bloc<RoomBlocEvent, RoomState>,
        RoomParticipantsHandlers,
        RoomPipHandlers,
        RoomEventsBinding {
  /// Signature of the set of remote participants that currently expose a
  /// camera (non-screen-share) video publication. Used to detect when a
  /// participant starts/stops publishing camera video so the camera grid can
  /// re-run its on-demand subscribe pass (see [_onSortParticipants]).
  String? _lastVideoPublicationSignature;

  /// Polls [SortParticipants] while remote users have camera enabled but no
  /// track yet (small meetings only).
  Timer? _pendingCameraVideoTrackTimer;

  void registerTracksHandlers() {
    on<SortParticipants>(_onSortParticipants);
    on<RefreshParticipantDisplayNames>(_onRefreshParticipantDisplayNames);
  }

  /// Whether any remote participant has a camera publication enabled but the
  /// track is not attached yet (common between publish and subscribe settle).
  bool _hasPendingCameraVideoTrackPublication() {
    for (final participant in state.room.remoteParticipants.values) {
      final hasPending = participant.videoTrackPublications.any(
        (pub) => !pub.isScreenShare && pub.enabled && pub.track == null,
      );
      if (hasPending) {
        return true;
      }
    }
    return false;
  }

  /// Build a stable signature of remote participants that have an enabled
  /// camera (non-screen-share) video publication. Includes participants whose
  /// track is not bound yet so the grid re-runs its on-demand subscribe pass
  /// as soon as the publication appears, not only after TrackSubscribed.
  String _computeVideoPublicationSignature() {
    final identities = <String>[];
    for (final participant in state.room.remoteParticipants.values) {
      final hasEnabledCameraPublication = participant.videoTrackPublications
          .any((pub) => !pub.isScreenShare && pub.enabled);

      if (hasEnabledCameraPublication) {
        identities.add(participant.identity);
      }
    }
    identities.sort();
    return identities.join(',');
  }

  /// Keeps a periodic sort alive while camera is enabled but track is missing.
  void _syncPendingCameraVideoTrackCheckTimer() {
    final remoteCount = state.room.remoteParticipants.length;
    if (remoteCount >= smallMeetingRemoteParticipantThreshold ||
        !_hasPendingCameraVideoTrackPublication()) {
      cancelPendingCameraVideoTrackCheckTimer();
      return;
    }

    _pendingCameraVideoTrackTimer ??= Timer.periodic(
      pendingCameraVideoTrackCheckInterval,
      (_) {
        if (isClosed) {
          cancelPendingCameraVideoTrackCheckTimer();
          return;
        }
        final currentRemoteCount = state.room.remoteParticipants.length;
        if (currentRemoteCount >= smallMeetingRemoteParticipantThreshold ||
            !_hasPendingCameraVideoTrackPublication()) {
          cancelPendingCameraVideoTrackCheckTimer();
          return;
        }
        add(SortParticipants());
      },
    );
  }

  void cancelPendingCameraVideoTrackCheckTimer() {
    _pendingCameraVideoTrackTimer?.cancel();
    _pendingCameraVideoTrackTimer = null;
  }

  Future<void> _onRefreshParticipantDisplayNames(
    RefreshParticipantDisplayNames event,
    Emitter<RoomState> emit,
  ) async {
    final updated = await loadFrbParticipants();
    emit(state.copyWith(frbParticipantsMap: updated));
    add(SortParticipants());
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
  /// - Local participant is inserted at the beginning unless [hideSelfCamera] is true
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
    // O(1) duplicate guard for userMediaTracks.
    final Set<String> seenIdentities = <String>{};
    final Set<String> screenShareSubscribeEnsured = <String>{};

    // reconcile in-flight audio subscribes, to avoid duplicate subscribes and improve performance
    reconcileInFlightAudioSubscribes();
    for (var participant in room.remoteParticipants.values) {
      final identity = participant.identity;
      bool hasVideo = false;
      for (var t in participant.videoTrackPublications) {
        hasVideo = true;
        if (t.isScreenShare) {
          if (screenShareSubscribeEnsured.add(t.sid)) {
            ensureScreenShareSubscribed(t);
          }

          /// Ensure high quality + 30 FPS for screen sharing.
          if (t.videoQuality != VideoQuality.HIGH) {
            t.setVideoQuality(VideoQuality.HIGH);
          }
          if (t.fps != 30) {
            t.setVideoFPS(30);
          }
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
          if (seenIdentities.add(identity)) {
            userMediaTracks.add(
              ParticipantInfo(
                displayName: displayName,
                participant: participant,
              ),
            );
          }
        } else {
          if (seenIdentities.add(identity)) {
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
        if (seenIdentities.add(identity)) {
          userMediaTracks.add(
            ParticipantInfo(
              displayName: getParticipantDisplayName(participant),
              participant: participant,
            ),
          );
        }
      }
    }

    /// sort speakers for the grid if participant count > 5 (otherwise they can show in same page, so no need to sort them)
    /// 1st: last spokeAt desc (if user spoke in 60 seconds, they will order by identity instead of spokeAt to avoid screen flickering)
    /// 2ed: has video move up, no video move down
    /// 3rd: joinAt asc
    const sortCountCheck = 2;
    if (userMediaTracks.length > sortCountCheck) {
      sortUserMediaTracksBySpoken(userMediaTracks);
    }

    final localParticipant = room.localParticipant;
    final localParticipantTracks = localParticipant?.videoTrackPublications;
    if (localParticipantTracks != null && localParticipantTracks.isNotEmpty) {
      for (final t in localParticipantTracks) {
        if (t.isScreenShare) {
          screenTracks.add(
            ParticipantInfo(
              participant: localParticipant!,
              type: ParticipantTrackType.kScreenShare,
              displayName: getParticipantDisplayName(
                localParticipant,
                isLocalScreenShare: true,
              ),
            ),
          );
        }
      }
    }

    if (localParticipant != null &&
        !hideSelfCamera &&
        seenIdentities.add(localParticipant.identity)) {
      userMediaTracks.insert(
        0,
        ParticipantInfo(
          displayName: getParticipantDisplayName(localParticipant),
          participant: localParticipant,
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
      add(const ToggleScreenShare());
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

    // Detect when a remote participant starts/stops publishing camera video.
    // With autoSubscribe:false the camera grid subscribes on demand from its
    // build() -> _updateVideoSubscriptions() pass, which only re-runs when
    // participantTracks changes identity/reference. A late camera publish
    // (ParticipantConnected fires before the track is published) keeps the
    // same identities/displayNames, so without this the grid never re-runs
    // the subscribe pass and the tile stays on NoVideoWidget until an
    // unrelated rebuild (e.g. window resize) happens.
    // Only check video publication signature in small meetings to avoid
    // unnecessary work in large rooms.
    bool videoAvailabilityChanged = false;
    if (room.remoteParticipants.length < smallMeetingRemoteParticipantThreshold) {
      final videoPublicationSignature = _computeVideoPublicationSignature();
      videoAvailabilityChanged =
          videoPublicationSignature != _lastVideoPublicationSignature;
      _lastVideoPublicationSignature = videoPublicationSignature;
    }
    // Emit a fresh participantTracks list when order or camera availability
    // changed so the BlocSelector feeding ResponsiveCameraLayout rebuilds.
    // Also refresh while a camera publication is enabled but track is not
    // bound yet so the grid keeps retrying subscribe during the in-flight gap.
    final isSmallMeeting =
        room.remoteParticipants.length < smallMeetingRemoteParticipantThreshold;
    final hasPendingCameraVideo =
        isSmallMeeting && _hasPendingCameraVideoTrackPublication();
    final shouldRefreshParticipantTracks =
        hasOrderChanged ||
        videoAvailabilityChanged ||
        hasPendingCameraVideo;

    // Only emit if something actually changed to reduce unnecessary rebuilds
    if (shouldRefreshParticipantTracks ||
        screenTracksChanged ||
        speakerTracksChanged ||
        screenSharingChanged ||
        cameraEnabledChanged) {
      emit(
        state.copyWith(
          participantTracks: shouldRefreshParticipantTracks
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

    _syncPendingCameraVideoTrackCheckTimer();

    // Active speaker / camera state can change without speaker list identity changing.
    scheduleIosPipSync();
  }

  List<ParticipantInfo> sortSpeakerTracks(List<ParticipantInfo> speakers) {
    sortParticipantsByActiveSpeakerPriority(
      speakers,
      state.raisedHandsByIdentity,
    );
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
    sortParticipantsByActiveSpeakerPriority(
      userMediaTracks,
      state.raisedHandsByIdentity,
    );
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
