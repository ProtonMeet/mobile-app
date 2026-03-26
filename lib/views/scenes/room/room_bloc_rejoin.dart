import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/helper/meet_join_link_parser.dart';
import 'package:meet/helper/video_track_publisher.dart';
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/room.manager.dart';
import 'package:meet/rust/errors.dart';
import 'package:meet/rust/proton_meet/models/meet_participant.dart';
import 'package:meet/rust/proton_meet/models/rejoin_reason.dart';
import 'package:meet/views/scenes/room/room_bloc.dart';
import 'package:meet/views/scenes/room/room_event.dart';
import 'package:meet/views/scenes/room/room_state.dart';
import 'package:sentry/sentry.dart';

/// Helper function to find matching device using smart matching logic
/// Priority: 1. Exact ID match, 2. Fallback to first available
MediaDevice? findMatchingDevice({
  required List<MediaDevice> availableDevices,
  required String deviceKind,
  String? savedDeviceId,
}) {
  if (availableDevices.isEmpty) return null;

  // Filter by device kind
  final devices = availableDevices.where((d) => d.kind == deviceKind).toList();
  if (devices.isEmpty) return null;

  // 1. Exact ID match
  if (savedDeviceId != null) {
    try {
      final exactMatch = devices.firstWhere((d) => d.deviceId == savedDeviceId);
      l.logger.i(
        '[RoomRejoin] Found exact device match by ID: ${exactMatch.deviceId}',
      );
      return exactMatch;
    } catch (e) {
      l.logger.d(
        '[RoomRejoin] No exact device match found for ID: $savedDeviceId',
      );
    }
  }

  // 2. Fallback to first available device
  l.logger.w(
    '[RoomRejoin] Using first available device as fallback: ${devices.first.deviceId}',
  );
  return devices.first;
}

/// Mixin for handling room rejoin after connection loss
mixin RoomRejoinHandlers on Bloc<RoomBlocEvent, RoomState> {
  void registerRejoinHandlers() {
    on<StartRejoinMeeting>(_onStartRejoinMeeting);
    on<RejoinMeetingProgress>(_onRejoinMeetingProgress);
    on<RejoinMeetingCompleted>(_onRejoinMeetingCompleted);
    on<RejoinMeetingFailed>(_onRejoinMeetingFailed);
    on<CancelRejoinMeeting>(_onCancelRejoinMeeting);
    on<SetRejoinFailedDialogShowing>(_onSetRejoinFailedDialogShowing);
    on<TriggerWebsocketReconnect>(_onTriggerWebsocketReconnect);
  }

  Future<void> _onStartRejoinMeeting(
    StartRejoinMeeting event,
    Emitter<RoomState> emit,
  ) async {
    // Check if auto reconnection feature is enabled
    if (this is RoomBloc) {
      final roomBloc = this as RoomBloc;
      if (!roomBloc.isMeetAutoReconnectionEnabled()) {
        l.logger.w(
          '[RoomRejoin] Auto reconnection feature disabled, skipping rejoin',
        );
        return;
      }
      // Check if room manager is initialized
      if (roomBloc.roomManager == null) {
        l.logger.w(
          '[RoomRejoin] Room manager not initialized, skipping rejoin',
        );
        return;
      }
    }

    // Prevent multiple rejoin attempts
    if (state.isRejoining) {
      l.logger.w('[RoomRejoin] Rejoin already in progress, skipping');
      return;
    }

    // Check if bloc is closed
    if (isClosed) {
      l.logger.w('[RoomRejoin] Bloc is closed, cannot start rejoin');
      return;
    }

    emit(
      state.copyWith(
        isRejoining: true,
        rejoinStatus: RejoinStatus.preparing,
        rejoinCount: state.rejoinCount + 1,
        rejoinStartedAt: DateTime.now(),
        rejoinReason: event.reason ?? RejoinReason.other,
      ),
    );

    try {
      // Use RoomBloc's room manager instance
      final roomBloc = this as RoomBloc;

      // Save current room state BEFORE connectToRoom (which may clear tracks)
      final oldRoom = state.room;
      final oldListener = state.listener;
      final oldDisplayName = state.displayName;
      final isAudioEnabled = oldRoom.localParticipant?.isMuted == false;
      final hadE2EE = oldRoom.e2eeManager != null;

      LocalAudioTrack? oldAudioTrack;
      LocalVideoTrack? oldVideoTrack;
      MediaDevice? oldAudioInputDevice;
      MediaDevice? oldAudioOutputDevice;
      MediaDevice? oldVideoInputDevice;
      bool wasAudioMuted = false;

      try {
        final oldLocalParticipant = oldRoom.localParticipant;
        if (oldLocalParticipant != null) {
          final audioPublications = oldLocalParticipant.audioTrackPublications;
          if (audioPublications.isNotEmpty) {
            final audioPub = audioPublications.first;
            wasAudioMuted = audioPub.muted;
            final track = audioPub.track;
            if (track is LocalAudioTrack) {
              oldAudioTrack = track;
            }
          }

          final videoPublications = oldLocalParticipant.videoTrackPublications
              .where((pub) => !pub.isScreenShare)
              .toList();
          if (videoPublications.isNotEmpty) {
            final videoPub = videoPublications.first;
            final track = videoPub.track;
            if (track is LocalVideoTrack) {
              oldVideoTrack = track;
            }
          }
        }

        try {
          final devices = await Hardware.instance.enumerateDevices();

          if (oldAudioTrack != null) {
            oldAudioInputDevice = findMatchingDevice(
              savedDeviceId: state.currentAudioInputDeviceId,
              availableDevices: devices,
              deviceKind: 'audioinput',
            );
            l.logger.i(
              '[RoomRejoin] Found audio input device: ${oldAudioInputDevice?.deviceId ?? "none"}',
            );
          }

          if (oldVideoTrack != null) {
            oldVideoInputDevice = findMatchingDevice(
              savedDeviceId: state.currentVideoInputDeviceId,
              availableDevices: devices,
              deviceKind: 'videoinput',
            );
            l.logger.i(
              '[RoomRejoin] Found video input device: ${oldVideoInputDevice?.deviceId ?? "none"}',
            );
          }

          oldAudioOutputDevice = findMatchingDevice(
            savedDeviceId: state.currentAudioOutputDeviceId,
            availableDevices: devices,
            deviceKind: 'audiooutput',
          );
          l.logger.i(
            '[RoomRejoin] Found audio output device: ${oldAudioOutputDevice?.deviceId ?? "none"}',
          );
        } catch (e) {
          l.logger.e('[RoomRejoin] Error getting devices: $e');
          // Continue even if device enumeration fails
        }
      } catch (e) {
        l.logger.e('[RoomRejoin] Error saving old room tracks: $e');
      }

      final meetLinkName = state.meetInfo.meetLinkName;
      final meetLinkParseResult = parseMeetJoinLink(state.meetingLink);
      final meetLinkPassword = meetLinkParseResult.passcode ?? '';

      if (meetLinkPassword.isEmpty) {
        if (kDebugMode) {
          l.logger.w(
            '[RoomRejoin] Could not parse password from meetingLink: ${state.meetingLink}',
          );
        }
        if (!isClosed) {
          add(
            RejoinMeetingFailed(
              error:
                  'Meeting password not found. Cannot rejoin without password.',
            ),
          );
        }
        return;
      }

      // Check if bloc is closed before continuing
      if (isClosed) {
        l.logger.w('[RoomRejoin] Bloc closed during rejoin, aborting');
        return;
      }

      emit(state.copyWith(rejoinStatus: RejoinStatus.reconnecting));

      // Get user config for room options with room manager (we had verified that room manager is initialized)
      final (cameraEncoding, screenEncoding) = await roomBloc.roomManager!
          .getUserConfig();

      // Check again after async operation
      if (isClosed) {
        l.logger.w('[RoomRejoin] Bloc closed during rejoin, aborting');
        return;
      }

      emit(state.copyWith(rejoinStatus: RejoinStatus.joining));
      // Create room options matching old room
      final roomOptions = RoomOptions(
        adaptiveStream: oldRoom.roomOptions.adaptiveStream,
        dynacast: oldRoom.roomOptions.dynacast,
        defaultAudioPublishOptions: const AudioPublishOptions(
          name: 'custom_audio_track_name',
        ),
        defaultCameraCaptureOptions: const CameraCaptureOptions(
          maxFrameRate: 30,
          params: VideoParameters(dimensions: VideoDimensions(1280, 720)),
        ),
        defaultScreenShareCaptureOptions: const ScreenShareCaptureOptions(
          useiOSBroadcastExtension: true,
          params: VideoParameters(dimensions: VideoDimensionsPresets.h1080_169),
        ),
        defaultVideoPublishOptions: VideoPublishOptions(
          simulcast: oldRoom.roomOptions.defaultVideoPublishOptions.simulcast,
          videoCodec: oldRoom.roomOptions.defaultVideoPublishOptions.videoCodec,
          backupVideoCodec: BackupVideoCodec(
            enabled: oldRoom
                .roomOptions
                .defaultVideoPublishOptions
                .backupVideoCodec
                .enabled,
          ),
          videoEncoding: cameraEncoding,
          screenShareEncoding: screenEncoding,
        ),
      );

      // Use helper to connect to room
      final shouldReuseToken = state.rejoinFailedCount == 0;
      RoomConnectionResult connectionResult;
      try {
        emit(state.copyWith(rejoinStatus: RejoinStatus.updatingAccessToken));
        connectionResult = await roomBloc.roomManager!.connectToRoom(
          RoomConnectionConfig(
            meetLinkName: meetLinkName,
            meetLinkPassword: meetLinkPassword,
            displayName: oldDisplayName,
            enableE2EE: hadE2EE,
            isAudioEnabled: isAudioEnabled,
            roomOptions: roomOptions,
            onRoomCreated: (room) {
              if (!isClosed) {
                emit(
                  state.copyWith(
                    rejoinStatus: RejoinStatus.creatingRoomConnection,
                  ),
                );
              }
            },
            onKeyRotationListenerSetup: (room) {
              if (!isClosed) {
                emit(
                  state.copyWith(
                    rejoinStatus: RejoinStatus.settingUpEncryption,
                  ),
                );
              }
            },
          ),
          oldRoom: oldRoom,
          reuseToken: shouldReuseToken,
        );

        // Check if bloc is closed before continuing
        if (isClosed) {
          l.logger.w('[RoomRejoin] Bloc closed during rejoin, aborting');
          return;
        }

        emit(state.copyWith(rejoinStatus: RejoinStatus.connectingToRoom));
      } catch (e) {
        // Log error to Sentry
        Sentry.captureException(
          e,
          stackTrace: e is Error ? e.stackTrace : null,
          withScope: (scope) {
            scope.setTag('room_action', 'rejoin_meeting');
            scope.setTag('rejoin_phase', 'connect_to_room');
            scope.setTag('meeting_link_name', state.meetInfo.meetLinkName);
            // Add error details if it's an API response error
            if (e is BridgeError_ApiResponse) {
              scope.setContexts('api_error', {
                'code': e.field0.code,
                'error': e.field0.error,
                'details': e.field0.details,
              });
            }
          },
        );

        if (!isClosed) {
          // Extract appropriate error message based on error type
          String errorMessage;
          if (e is BridgeError_ApiResponse) {
            // Use the error message from API response
            errorMessage = e.field0.error;
          } else {
            // Use the string representation for other error types
            errorMessage = e.toString();
          }
          add(RejoinMeetingFailed(error: errorMessage));
        }
        return;
      }

      // Check if bloc is closed before continuing
      if (isClosed) {
        l.logger.w('[RoomRejoin] Bloc closed during rejoin, aborting');
        // Clean up connection result if bloc is closed
        try {
          await connectionResult.room.disconnect();
          await connectionResult.room.dispose();
          await connectionResult.listener.dispose();
          await connectionResult.dispose();
        } catch (e) {
          l.logger.e('[RoomRejoin] Error cleaning up after abort: $e');
        }
        return;
      }

      final newRoom = connectionResult.room;
      final newListener = connectionResult.listener;
      final meetInfo = connectionResult.meetInfo;

      // Cancel old subscriptions and set new ones
      // This is safe because RoomRejoinHandlers is only used by RoomBloc
      if (this is RoomBloc) {
        final roomBloc = this as RoomBloc;
        roomBloc.setKeyRotationSubscription(
          connectionResult.keyRotationSubscription,
        );
        roomBloc.setupMlsSyncStateListener();
      }

      // Check if bloc is closed before continuing
      if (isClosed) {
        l.logger.w('[RoomRejoin] Bloc closed during rejoin, aborting');
        // Clean up new room if bloc is closed
        try {
          await newRoom.disconnect();
          await newRoom.dispose();
          await newListener.dispose();
        } catch (e) {
          l.logger.e('[RoomRejoin] Error cleaning up new room after abort: $e');
        }
        return;
      }

      // Clean up old room
      emit(state.copyWith(rejoinStatus: RejoinStatus.finalizingConnection));
      try {
        // Remove old listener
        await oldListener.cancelAll();
        await oldListener.dispose();
        await oldRoom.disconnect();
        await oldRoom.dispose();
      } catch (e) {
        l.logger.e('[RoomRejoin] Error cleaning up old room: $e');
      }

      // Check again after cleanup
      if (isClosed) {
        l.logger.w('[RoomRejoin] Bloc closed during rejoin, aborting');
        // Clean up new room if bloc is closed
        try {
          await newRoom.disconnect();
          await newRoom.dispose();
          await newListener.dispose();
        } catch (e) {
          l.logger.e('[RoomRejoin] Error cleaning up new room after abort: $e');
        }
        return;
      }

      // Republish tracks to new room
      emit(state.copyWith(rejoinStatus: RejoinStatus.republishingTracks));
      try {
        final newLocalParticipant = newRoom.localParticipant;
        if (newLocalParticipant != null) {
          try {
            if (oldAudioInputDevice != null) {
              await newRoom.setAudioInputDevice(oldAudioInputDevice);
              l.logger.i(
                '[RoomRejoin] Audio input device set: ${oldAudioInputDevice.deviceId}',
              );
            }
            if (oldAudioOutputDevice != null) {
              await newRoom.setAudioOutputDevice(oldAudioOutputDevice);

              if (android) {
                await Hardware.instance.selectAudioOutput(oldAudioOutputDevice);
                // workaround to refresh speakerphone state on the new device (need to set it to the opposite state first or it cannot load bluetooth device correctly), didn't find a proper way to fix this after few tries
                // To-do: improve this
                Hardware.instance.setSpeakerphoneOn(!state.isSpeakerPhone);
                await Future.delayed(
                  const Duration(milliseconds: 100),
                ); // delay to ensure speakerphone state is applied
                Hardware.instance.setSpeakerphoneOn(state.isSpeakerPhone);
                await Future.delayed(
                  const Duration(milliseconds: 100),
                ); // delay to ensure speakerphone state is applied
              } else {
                await Hardware.instance.selectAudioOutput(oldAudioOutputDevice);
              }
              l.logger.i(
                '[RoomRejoin] Audio output device set: ${oldAudioOutputDevice.deviceId}',
              );
            }
            if (oldVideoInputDevice != null) {
              await newRoom.setVideoInputDevice(oldVideoInputDevice);
              l.logger.i(
                '[RoomRejoin] Video input device set: ${oldVideoInputDevice.deviceId}',
              );
            }
          } catch (e) {
            l.logger.e('[RoomRejoin] Error setting devices: $e');
            // Continue even if device setting fails - tracks will use default devices
          }

          final currentCameraEnabled = state.isCameraEnabled;
          // For audio, check if audio was enabled before rejoin started
          final currentAudioEnabled = oldAudioTrack != null && !wasAudioMuted;

          l.logger.i(
            '[RoomRejoin] Republishing tracks with current state: '
            'audio=$currentAudioEnabled,'
            'camera=$currentCameraEnabled',
          );

          // Republish audio track if it existed before AND was enabled
          if (oldAudioTrack != null && currentAudioEnabled) {
            try {
              // Stop old track first
              await oldAudioTrack.stop();

              // Create new audio track with same device settings as before
              LocalAudioTrack newAudioTrack;
              if (oldAudioInputDevice != null) {
                newAudioTrack = await LocalAudioTrack.create(
                  AudioCaptureOptions(deviceId: oldAudioInputDevice.deviceId),
                );
              } else {
                // Fallback to default device
                newAudioTrack = await LocalAudioTrack.create();
              }
              await newAudioTrack.start();

              // Publish to new room
              await newLocalParticipant.publishAudioTrack(newAudioTrack);

              // Verify audio track was published successfully
              final audioPubs = newLocalParticipant.audioTrackPublications;
              if (audioPubs.isEmpty) {
                l.logger.w(
                  '[RoomRejoin] Audio track published but not found in publications',
                );
              } else {
                l.logger.i('[RoomRejoin] Audio track republished successfully');
              }

              // Ensure microphone is enabled after republishing track
              if (!wasAudioMuted) {
                await newLocalParticipant.setMicrophoneEnabled(true);
                l.logger.i(
                  '[RoomRejoin] Microphone enabled after republishing audio track',
                );
              } else {
                // If audio was muted before, keep it muted
                await newLocalParticipant.setMicrophoneEnabled(false);
                l.logger.i(
                  '[RoomRejoin] Microphone muted (was muted before rejoin)',
                );
              }
            } catch (e) {
              l.logger.e('[RoomRejoin] Failed to republish audio track: $e');
              // Continue even if audio republish fails
            }
          } else {
            try {
              await newLocalParticipant.setMicrophoneEnabled(false);
              l.logger.i(
                '[RoomRejoin] Audio disabled (was: ${oldAudioTrack != null}, now: $currentAudioEnabled)',
              );
            } catch (e) {
              l.logger.e('[RoomRejoin] Error disabling microphone: $e');
            }
          }

          // Republish video track if it existed and currently enabled
          if (oldVideoTrack != null && currentCameraEnabled) {
            LocalVideoTrack? publishedVideoTrack;
            try {
              // Stop old track first
              await oldVideoTrack.stop();

              // Get video parameters from old room
              final videoParams = oldRoom
                  .roomOptions
                  .defaultCameraCaptureOptions
                  .params
                  .dimensions;
              final preferredCodec =
                  oldRoom.roomOptions.defaultVideoPublishOptions.videoCodec;

              // Create new video track with same parameters and device
              // For mobile devices, prefer CameraPosition; for desktop, use deviceId
              LocalVideoTrack newVideoTrack;
              final currentCameraPosition = state.currentCameraPosition;

              if (currentCameraPosition != null) {
                // Mobile device: use CameraPosition
                newVideoTrack = await LocalVideoTrack.createCameraTrack(
                  CameraCaptureOptions(
                    cameraPosition: currentCameraPosition,
                    params: VideoParameters(dimensions: videoParams),
                  ),
                );
                l.logger.i(
                  '[RoomRejoin] Creating video track with camera position: $currentCameraPosition',
                );
              } else if (oldVideoInputDevice != null) {
                // Desktop device: use deviceId
                newVideoTrack = await LocalVideoTrack.createCameraTrack(
                  CameraCaptureOptions(
                    deviceId: oldVideoInputDevice.deviceId,
                    params: VideoParameters(dimensions: videoParams),
                  ),
                );
                l.logger.i(
                  '[RoomRejoin] Creating video track with device: ${oldVideoInputDevice.deviceId}',
                );
              } else {
                // Fallback: use default device
                newVideoTrack = await LocalVideoTrack.createCameraTrack(
                  CameraCaptureOptions(
                    params: VideoParameters(dimensions: videoParams),
                  ),
                );
                l.logger.w(
                  '[RoomRejoin] Creating video track with default device',
                );
              }
              await newVideoTrack.start();

              // Publish to new room with fallback (similar to waiting_room_bloc)
              final publishOptions = newRoom
                  .roomOptions
                  .defaultVideoPublishOptions
                  .copyWith(videoCodec: preferredCodec);
              publishedVideoTrack = await publishVideoTrackWithFallback(
                participant: newLocalParticipant,
                initialTrack: newVideoTrack,
                createTrack: () async {
                  // Recreate track for fallback if needed
                  LocalVideoTrack track;
                  final currentCameraPosition = state.currentCameraPosition;

                  if (currentCameraPosition != null) {
                    // Mobile device: use CameraPosition
                    track = await LocalVideoTrack.createCameraTrack(
                      CameraCaptureOptions(
                        cameraPosition: currentCameraPosition,
                        params: VideoParameters(dimensions: videoParams),
                      ),
                    );
                  } else if (oldVideoInputDevice != null) {
                    // Desktop device: use deviceId
                    track = await LocalVideoTrack.createCameraTrack(
                      CameraCaptureOptions(
                        deviceId: oldVideoInputDevice.deviceId,
                        params: VideoParameters(dimensions: videoParams),
                      ),
                    );
                  } else {
                    // Fallback: use default device
                    track = await LocalVideoTrack.createCameraTrack(
                      CameraCaptureOptions(
                        params: VideoParameters(dimensions: videoParams),
                      ),
                    );
                  }
                  await track.start();
                  return track;
                },
                publishOptions: publishOptions,
              );

              // Verify video track was published successfully
              // Wait a bit for publication to propagate
              await Future.delayed(const Duration(milliseconds: 500));
              final videoPubs = newLocalParticipant.videoTrackPublications
                  .where((pub) => !pub.isScreenShare)
                  .toList();
              if (videoPubs.isEmpty) {
                l.logger.w(
                  '[RoomRejoin] Video track published but not found in publications, waiting longer...',
                );
                // Wait a bit more and check again
                await Future.delayed(const Duration(milliseconds: 1000));
                final retryVideoPubs = newLocalParticipant
                    .videoTrackPublications
                    .where((pub) => !pub.isScreenShare)
                    .toList();
                if (retryVideoPubs.isEmpty) {
                  l.logger.e(
                    '[RoomRejoin] Video track still not found in publications after retry',
                  );
                  // Clean up failed track but don't throw - allow rejoin to continue
                  try {
                    await publishedVideoTrack.stop();
                    await publishedVideoTrack.dispose();
                  } catch (disposeError) {
                    l.logger.e(
                      '[RoomRejoin] Error disposing failed video track: $disposeError',
                    );
                  }
                  // Log error but continue - user can manually enable video later
                } else {
                  l.logger.i('[RoomRejoin] Video track found after retry');
                }
              } else {
                // Verify the published track matches
                final publishedTrack = videoPubs.first.track;
                if (publishedTrack == null) {
                  l.logger.w(
                    '[RoomRejoin] Video track publication exists but track is null',
                  );
                } else {
                  l.logger.i(
                    '[RoomRejoin] Video track republished successfully and verified',
                  );
                }
              }

              if (!currentCameraEnabled) {
                await newLocalParticipant.setCameraEnabled(false);
                l.logger.i(
                  '[RoomRejoin] Video muted state restored (disabled)',
                );
              }
            } catch (e) {
              l.logger.e('[RoomRejoin] Failed to republish video track: $e');
              // Clean up failed track
              try {
                await publishedVideoTrack?.stop();
                await publishedVideoTrack?.dispose();
              } catch (cleanupError) {
                l.logger.e(
                  '[RoomRejoin] Error cleaning up failed video track: $cleanupError',
                );
              }
              // Continue even if video republish fails
            }
          } else if (!currentCameraEnabled) {
            // Ensure video is disabled if currently disabled
            try {
              await newLocalParticipant.setCameraEnabled(false);
            } catch (e) {
              l.logger.e('[RoomRejoin] Error disabling camera: $e');
            }
          }
        }
      } catch (e) {
        l.logger.e('[RoomRejoin] Error republishing tracks: $e');
        // Continue even if track republish fails - user can manually enable later
      }

      // Check if bloc is closed before updating state
      if (isClosed) {
        l.logger.w('[RoomRejoin] Bloc closed during rejoin, aborting');
        // Clean up new room if bloc is closed
        try {
          await newRoom.disconnect();
          await newRoom.dispose();
          await newListener.dispose();
        } catch (e) {
          l.logger.e('[RoomRejoin] Error cleaning up new room after abort: $e');
        }
        return;
      }

      // Update state with new room
      // We need to create a new RoomState since room, listener, and meetInfo are required
      // Keep isRejoining and rejoinStatus until RejoinMeetingCompleted event is processed
      final newState = RoomState(
        room: newRoom,
        listener: newListener,
        meetInfo: meetInfo,
        displayName: state.displayName,
        frbParticipantsMap: state.frbParticipantsMap,
        roomKey: state.roomKey,
        epoch: state.epoch,
        displayCode: state.displayCode,
        participantsCount: state.participantsCount,
        participantTracks: state.participantTracks,
        screenSharingTracks: state.screenSharingTracks,
        speakerTracks: state.speakerTracks,
        messages: state.messages,
        joinedParticipants: state.joinedParticipants,
        leftParticipants: state.leftParticipants,
        showChatBubble: state.showChatBubble,
        showParticipantList: state.showParticipantList,
        isFullScreen: state.isFullScreen,
        hideSelfCamera: state.hideSelfCamera,
        fps: state.fps,
        videoQuality: state.videoQuality,
        layout: state.layout,
        isLocalScreenSharing: state.isLocalScreenSharing,
        isRemoteScreenSharing: state.isRemoteScreenSharing,
        screenSharingIndex: state.screenSharingIndex,
        unsubscribeVideoByDefault: state.unsubscribeVideoByDefault,
        meetingLink: state.meetingLink,
        showMeetingIsReady: state.showMeetingIsReady,
        isSpeakerMuted: state.isSpeakerMuted,
        shouldShowMeetingWillEndDialog: state.shouldShowMeetingWillEndDialog,
        aloneSince: state.aloneSince,
        isPictureInPictureActive: state.isPictureInPictureActive,
        pipVideoTrackSid: state.pipVideoTrackSid,
        pipParticipantIdentity: state.pipParticipantIdentity,
        isPipMode: state.isPipMode,
        pipInitialized: state.pipInitialized,
        pipAvailable: state.pipAvailable,
        isCameraEnabled: state.isCameraEnabled,
        isSpeakerPhone: state.isSpeakerPhone,
        isMeetMobileSpeakerToggleEnabled:
            state.isMeetMobileSpeakerToggleEnabled,
        isPaidUser: state.isPaidUser,
        meetingInfo: state.meetingInfo,
        currentCameraPosition: state.currentCameraPosition,
        audioDeviceCount: state.audioDeviceCount,
        isRoomInitialized: state.isRoomInitialized,
        isTrackInitialized: state.isTrackInitialized,
        isRejoining: state.isRejoining,
        rejoinStatus: state.rejoinStatus,
        rejoinError: state.rejoinError,
        rejoinFailedCount: state.rejoinFailedCount,
        rejoinCompletedAt: state.rejoinCompletedAt,
        rejoinCount: state.rejoinCount,
        rejoinStartedAt: state.rejoinStartedAt,
        rejoinReason: state.rejoinReason,
        mlsSyncState: state.mlsSyncState,
        forceShowConnectionStatusBanner: state.forceShowConnectionStatusBanner,
        currentAudioInputDeviceId: state.currentAudioInputDeviceId,
        currentVideoInputDeviceId: state.currentVideoInputDeviceId,
        currentAudioOutputDeviceId: state.currentAudioOutputDeviceId,
      );
      emit(newState);

      if (!isClosed) {
        add(RejoinMeetingCompleted());
      }
    } catch (e) {
      l.logger.e('[RoomRejoin] Unexpected error during rejoin: $e');
      Sentry.captureException(
        e,
        stackTrace: e is Error ? e.stackTrace : null,
        withScope: (scope) {
          scope.setTag('room_action', 'rejoin_meeting');
          scope.setTag('meeting_link_name', state.meetInfo.meetLinkName);
          // Add error details if it's an API response error
          if (e is BridgeError_ApiResponse) {
            scope.setContexts('api_error', {
              'code': e.field0.code,
              'error': e.field0.error,
              'details': e.field0.details,
            });
          }
        },
      );
      if (!isClosed) {
        // Extract appropriate error message based on error type
        String errorMessage;
        if (e is BridgeError_ApiResponse) {
          // Use the error message from API response
          errorMessage = e.field0.error;
        } else {
          // Use the string representation for other error types
          errorMessage = e.toString();
        }
        add(RejoinMeetingFailed(error: errorMessage));
      }
    }
  }

  Future<void> _onRejoinMeetingProgress(
    RejoinMeetingProgress event,
    Emitter<RoomState> emit,
  ) async {
    emit(state.copyWith(rejoinStatus: event.status));
  }

  Future<void> _onRejoinMeetingCompleted(
    RejoinMeetingCompleted event,
    Emitter<RoomState> emit,
  ) async {
    // Calculate rejoin duration
    final rejoinStartedAt = state.rejoinStartedAt;
    final rejoinReason = state.rejoinReason ?? RejoinReason.other;
    final rejoinCount = state.rejoinCount;

    BigInt rejoinTimeMs = BigInt.zero;
    if (rejoinStartedAt != null) {
      final duration = DateTime.now().difference(rejoinStartedAt);
      rejoinTimeMs = BigInt.from(duration.inMilliseconds);
    }

    if (this is RoomBloc) {
      final roomBloc = this as RoomBloc;
      await roomBloc.logUserRejoin(
        rejoinTimeMs: rejoinTimeMs,
        incrementalCount: rejoinCount,
        reason: rejoinReason,
        success: true,
      );
    }

    Map<String, MeetParticipant>? updatedFrbParticipantsMap;
    try {
      if (this is RoomBloc) {
        final roomBloc = this as RoomBloc;
        updatedFrbParticipantsMap = await roomBloc.loadFrbParticipants();
      }
    } catch (e, stackTrace) {
      l.logger.e(
        '[RoomRejoin] Error loading FRB participants after rejoin: $e',
        error: e,
        stackTrace: stackTrace,
      );
    }

    emit(
      state.copyWith(
        isRejoining: false,
        // ignore: avoid_redundant_argument_values
        rejoinStatus: null,
        // ignore: avoid_redundant_argument_values
        rejoinError: null,
        rejoinFailedCount: 0,
        rejoinCompletedAt: DateTime.now(),
        // ignore: avoid_redundant_argument_values
        rejoinStartedAt: null, // Clear start time
        // ignore: avoid_redundant_argument_values
        rejoinReason: null, // Clear reason
        frbParticipantsMap:
            updatedFrbParticipantsMap ?? state.frbParticipantsMap,
      ),
    );
    l.logger.i('[RoomRejoin] Rejoin completed successfully');
  }

  Future<void> _onRejoinMeetingFailed(
    RejoinMeetingFailed event,
    Emitter<RoomState> emit,
  ) async {
    final newFailedCount = state.rejoinFailedCount + 1;
    l.logger.e(
      '[RoomRejoin] Rejoin failed: ${event.error} (failed count: $newFailedCount)',
    );

    // Calculate rejoin duration
    final rejoinStartedAt = state.rejoinStartedAt;
    final rejoinReason = state.rejoinReason ?? RejoinReason.other;
    final rejoinCount = state.rejoinCount;

    BigInt rejoinTimeMs = BigInt.zero;
    if (rejoinStartedAt != null) {
      final duration = DateTime.now().difference(rejoinStartedAt);
      rejoinTimeMs = BigInt.from(duration.inMilliseconds);
    }

    if (this is RoomBloc) {
      final roomBloc = this as RoomBloc;
      await roomBloc.logUserRejoin(
        rejoinTimeMs: rejoinTimeMs,
        incrementalCount: rejoinCount,
        reason: rejoinReason,
        success: false,
      );
    }

    // Increment failed count
    emit(state.copyWith(rejoinFailedCount: newFailedCount));

    // If this is the first failure (count == 1), automatically retry with reuseToken=false
    if (newFailedCount == 1) {
      l.logger.i(
        '[RoomRejoin] First failure, automatically retrying with reuseToken=false',
      );
      // Clear rejoin status and error
      emit(
        state.copyWith(
          isRejoining: false,
          // ignore: avoid_redundant_argument_values
          rejoinStatus: null,
          // ignore: avoid_redundant_argument_values
          rejoinError: null,
        ),
      );
      if (!isClosed) {
        // Retry with same reason as original attempt
        add(StartRejoinMeeting(reason: rejoinReason));
      }
    } else {
      // Second failure or more, show error dialog, let user to decide to leave or rejoin manually
      emit(
        state.copyWith(
          isRejoining: false,
          rejoinStatus: RejoinStatus.error,
          rejoinError: event.error,
        ),
      );
    }
  }

  Future<void> _onCancelRejoinMeeting(
    CancelRejoinMeeting event,
    Emitter<RoomState> emit,
  ) async {
    emit(
      state.copyWith(
        isRejoining: false,
        // ignore: avoid_redundant_argument_values
        rejoinStatus: null,
        // ignore: avoid_redundant_argument_values
        rejoinError: null,
        isRejoinFailedDialogShowing: false,
      ),
    );
  }

  Future<void> _onSetRejoinFailedDialogShowing(
    SetRejoinFailedDialogShowing event,
    Emitter<RoomState> emit,
  ) async {
    emit(state.copyWith(isRejoinFailedDialogShowing: event.isShowing));
  }

  Future<void> _onTriggerWebsocketReconnect(
    TriggerWebsocketReconnect event,
    Emitter<RoomState> emit,
  ) async {
    try {
      final appCoreManager = ManagerFactory().get<AppCoreManager>();
      await appCoreManager.appCore.triggerWebsocketReconnect();
      l.logger.i('[RoomRejoin] WebSocket reconnection triggered');
    } catch (e) {
      l.logger.e('[RoomRejoin] Failed to trigger WebSocket reconnection: $e');
    }
  }
}
