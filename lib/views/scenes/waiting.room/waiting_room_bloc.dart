import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/helper/extension/bridge_error.extension.dart';
import 'package:meet/helper/extension/local_video_track_extension.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/helper/video_track_publisher.dart';
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/channels/platform_info_channel.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/managers/room.manager.dart';
import 'package:meet/managers/services/force_upgrade.dart';
import 'package:meet/rust/errors.dart';
import 'package:meet/rust/proton_meet/models/meeting_type.dart';
import 'package:meet/rust/proton_meet/models/upcoming_meeting.dart';
import 'package:meet/rust/proton_meet/user_subscription.dart';
import 'package:meet/views/scenes/prejoin/prejoin_arguments.dart';
import 'package:sentry/sentry.dart';

import 'waiting_room_error_code.dart';
import 'waiting_room_event.dart';
import 'waiting_room_state.dart';

class WaitingRoomBloc extends Bloc<WaitingRoomEvent, WaitingRoomState> {
  // Subscription for key rotation listener (designated committer logging)
  StreamSubscription<(String, BigInt)?>? _keyRotationLoggingSubscription;
  // Subscription from RoomConnectionHelper for key rotation handling
  StreamSubscription<(String, BigInt)?>? _keyRotationHandlingSubscription;

  WaitingRoomBloc()
    : super(
        WaitingRoomState(
          args: JoinArgs(meetingLink: FrbUpcomingMeeting.defaultValues()),
          preJoinType: PreJoinType.join,
        ),
      ) {
    on<WaitingRoomInitialized>(_onInitialized);
    on<WaitingRoomSetupRoomKey>(_onSetupRoomKey);
    on<WaitingRoomNavigateToRoom>(_onNavigateToRoom);
    on<WaitingRoomDisconnectOnError>(_onDisconnectOnError);

    on<WaitingRoomEvent>((event, emit) {
      if (event is! WaitingRoomDisconnectOnError) {
        if (PlatformInfoChannel.isInForceUpgradeState()) {
          return;
        }
        emit(state.copyWith(isLoading: true));
      }
    });
  }

  /// Cancel all key rotation subscriptions
  void _cancelKeyRotationSubscriptions() {
    _keyRotationLoggingSubscription?.cancel();
    _keyRotationLoggingSubscription = null;
    _keyRotationHandlingSubscription?.cancel();
    _keyRotationHandlingSubscription = null;
  }

  Future<void> _onInitialized(
    WaitingRoomInitialized event,
    Emitter<WaitingRoomState> emit,
  ) async {
    if (PlatformInfoChannel.isInForceUpgradeState()) {
      emit(
        state.copyWith(
          isLoading: false,
          error: kDefaultForceUpgradeMessage,
          currentStatus: 'Update required',
          statusDescription: '',
        ),
      );
      return;
    }
    // room-related variables, need to be declared outside try block so they can be accessed in catch for disconnect and cleanup
    Room? room;
    EventsListener<RoomEvent>? listener;
    LocalAudioTrack? audioTrack;
    LocalVideoTrack? videoTrack;

    try {
      final appCoreManager = ManagerFactory().get<AppCoreManager>();
      final heading = "Launching Meeting...";
      final description = 'Encrypting with Messaging Layer Security (MLS)';
      emit(
        state.copyWith(currentStatus: heading, statusDescription: description),
      );
      bool isPaidUser = false;
      try {
        if (appCoreManager.isAuthenticated) {
          final userState = await appCoreManager.appCore.fetchUserState(
            userId: appCoreManager.userID!,
          );
          isPaidUser = isPaid(user: userState.userData);
        }
      } catch (e) {
        l.logger.e("error fetching user state: $e");
      }

      FrbUpcomingMeeting? meetLink = event.args.meetingLink;
      if (event.preJoinType == PreJoinType.create) {
        final meetingName = isPaidUser ? "Secure meeting" : "Free meeting";
        try {
          meetLink = await appCoreManager.appCore.createMeeting(
            meetingName: meetingName,
            hasSession: appCoreManager.isAuthenticated,
            meetingType: MeetingType.instant,
          );
          emit(state.copyWith(meetLink: meetLink));
        } catch (e) {
          logBridgeError('WaitingRoomBloc', 'Error creating meeting', e);
          emit(state.copyWith(error: extractErrorMessage(e)));
          return;
        }
      } else {
        emit(
          state.copyWith(
            currentStatus: heading,
            statusDescription: description,
          ),
        );
      }

      if (meetLink != null) {
        final roomManager = RoomManager(appCoreManager);

        // Get user config for room options
        final (cameraEncoding, screenEncoding) = await roomManager
            .getUserConfig();

        // Create room options
        final roomOptions = RoomOptions(
          adaptiveStream: event.args.adaptiveStream,
          dynacast: event.args.dynacast,
          defaultAudioPublishOptions: const AudioPublishOptions(
            name: 'custom_audio_track_name',
          ),
          defaultCameraCaptureOptions: const CameraCaptureOptions(
            maxFrameRate: 30,
            params: VideoParameters(dimensions: VideoDimensions(1280, 720)),
          ),
          defaultScreenShareCaptureOptions: const ScreenShareCaptureOptions(
            useiOSBroadcastExtension: true,
            params: VideoParameters(
              dimensions: VideoDimensionsPresets.h1080_169,
            ),
          ),
          defaultVideoPublishOptions: VideoPublishOptions(
            simulcast: event.args.simulcast,
            videoCodec: event.args.preferredCodec,
            backupVideoCodec: BackupVideoCodec(
              enabled: event.args.enableBackupVideoCodec,
            ),
            videoEncoding: cameraEncoding,
            screenShareEncoding: screenEncoding,
          ),
        );

        // Use helper to connect to room
        RoomConnectionResult connectionResult;
        try {
          connectionResult = await roomManager.connectToRoom(
            RoomConnectionConfig(
              meetLinkName: meetLink.meetingLinkName,
              meetLinkPassword: meetLink.meetingPassword,
              displayName: event.args.displayName,
              enableE2EE: event.enableE2EE,
              isAudioEnabled: event.isAudioEnabled,
              roomOptions: roomOptions,
              onCreateAudioTrack: (room) async {
                // Create audio track after prepareConnection and pre-connect E2EE keys if needed
                if (event.selectedAudioDevice != null && event.isAudioEnabled) {
                  final track = await LocalAudioTrack.create(
                    AudioCaptureOptions(
                      autoGainControl: false,
                      deviceId: event.selectedAudioDevice!.deviceId,
                    ),
                  );
                  await track.start();
                  audioTrack = track;
                  return track;
                }
                return null;
              },
              onKeyRotationListenerSetup: (room) {
                // Cancel any existing subscription before creating a new one
                _keyRotationLoggingSubscription?.cancel();
                // Log designated committer for key rotation
                _keyRotationLoggingSubscription = appCoreManager
                    .mlsGroupKeyStream
                    .listen((groupKeyInfo) async {
                      if (groupKeyInfo != null) {
                        final epoch = groupKeyInfo.$2;
                        try {
                          await appCoreManager.appCore
                              .tryLogDesignatedCommitter(epoch: epoch.toInt());
                        } catch (e) {
                          l.logger.e("error logging designated committer: $e");
                        }
                      }
                    });
              },
            ),
          );

          // Create video track after connection (as in original code)
          if (event.selectedVideoDevice != null && event.isVideoEnabled) {
            final track = await LocalVideoTrack.createCameraTrack(
              CameraCaptureOptions(
                deviceId: event.selectedVideoDevice!.deviceId,
                params: event.selectedVideoParameters,
              ),
            );
            await track.start();
            videoTrack = track;
          }
        } catch (e) {
          // Check if meeting is locked, which is an expected error
          if (e is BridgeError_MeetingLocked) {
            l.logger.e('[WaitingRoomBloc] Meeting is locked: $e');
            emit(
              state.copyWith(
                isLoading: false,
                error: WaitingRoomErrorCode.meetingLocked.name,
              ),
            );
            return;
          }

          // Log join meeting failed to meet-server if feature flag is enabled
          try {
            final dataProviderManager = ManagerFactory()
                .get<DataProviderManager>();
            if (dataProviderManager.unleashDataProvider
                .isMeetClientMetricsLog()) {
              String? errorCode;
              if (e is Exception) {
                errorCode = e.toString();
              }
              await appCoreManager.appCore.logJoinedRoomFailed(
                errorCode: errorCode ?? "Failed to join meeting",
              );
            }
          } catch (logError) {
            l.logger.w(
              '[WaitingRoomBloc] Error logging join meeting failed: $logError',
            );
          }

          // Send join meeting failure to Sentry with context
          final meetingLinkName =
              event.args.meetingLink?.meetingLinkName ?? 'unknown';
          Sentry.captureException(
            e,
            stackTrace: e is Error ? e.stackTrace : null,
            withScope: (scope) {
              scope.setTag('error_type', 'join_meeting_failed');
              scope.setTag('meeting_link_name', meetingLinkName);
              scope.setContexts('join_meeting_details', {
                'enable_e2ee': event.enableE2EE.toString(),
                'audio_enabled': event.isAudioEnabled.toString(),
                'video_enabled': event.isVideoEnabled.toString(),
              });
            },
          );

          rethrow; // rethrow the error to be handled by the bloc listener in waiting_room_view.dart
        }

        room = connectionResult.room;
        listener = connectionResult.listener;
        final meetInfo = connectionResult.meetInfo;
        final keyProvider = connectionResult.keyProvider;

        // Set meetingLinkName in Sentry scope for global error tracking
        // Only set meetingLinkName, not password, to avoid leaking sensitive data
        await Sentry.configureScope((scope) async {
          await scope.setTag('meeting_link_name', meetInfo.meetLinkName);
        });

        // Save the key rotation subscription from RoomConnectionHelper
        _keyRotationHandlingSubscription =
            connectionResult.keyRotationSubscription;

        emit(
          state.copyWith(
            statusDescription: meetInfo.participantsCount > 0
                ? 'Joining meeting with ${meetInfo.participantsCount} other participants'
                : 'Starting meeting as the first participant',
          ),
        );

        // Manually publish video track with preferred codec first and fallback to VP8 if failed.
        if (videoTrack != null && room.localParticipant != null) {
          final preferredCodec =
              room.roomOptions.defaultVideoPublishOptions.videoCodec;
          final currentVideoTrack = videoTrack;
          final localParticipant = room.localParticipant!;
          try {
            videoTrack = await publishVideoTrackWithFallback(
              participant: localParticipant,
              initialTrack: currentVideoTrack,
              createTrack: () async {
                // Recreate track for fallback publish if needed
                final track = await LocalVideoTrack.createCameraTrack(
                  CameraCaptureOptions(
                    deviceId: event.selectedVideoDevice!.deviceId,
                    params: event.selectedVideoParameters,
                  ),
                );
                await track.start();
                return track;
              },
              publishOptions: room.roomOptions.defaultVideoPublishOptions
                  .copyWith(videoCodec: preferredCodec),
            );
          } catch (e) {
            l.logger.e('[WaitingRoom] Failed to publish video track: $e');
            // Clean up video track if publish fails; let user join without video.
            try {
              await videoTrack?.stop();
            } catch (stopError) {
              l.logger.e(
                '[WaitingRoom] Error stopping video track: $stopError',
              );
            }
          }
        }

        /// set devices, so room can know the latest settings
        if (event.selectedAudioDevice != null) {
          await room.setAudioInputDevice(event.selectedAudioDevice!);
        }
        if (event.selectedVideoDevice != null) {
          await room.setVideoInputDevice(event.selectedVideoDevice!);
        }
        if (event.selectedSpeakerDevice != null) {
          await room.setAudioOutputDevice(event.selectedSpeakerDevice!);
        }

        emit(
          state.copyWith(
            isLoading: false,
            room: room,
            listener: listener,
            audioTrack: audioTrack,
            videoTrack: videoTrack,
            selectedVideoPosition: event.selectedVideoPosition,
            args: event.args,
            meetInfo: meetInfo,
            meetLink: event.args.meetingLink,
            keyProvider: keyProvider,
          ),
        );

        add(WaitingRoomSetupRoomKey());
      } else {
        emit(
          state.copyWith(
            isLoading: false,
            error: "Meet link not found, please try again",
          ),
        );
        // Log join room failed if feature flag is enabled
        try {
          final dataProviderManager = ManagerFactory()
              .get<DataProviderManager>();
          if (dataProviderManager.unleashDataProvider
              .isMeetClientMetricsLog()) {
            await appCoreManager.appCore.logJoinedRoomFailed(
              errorCode: "Meet link not found",
            );
          }
        } catch (logError) {
          logBridgeError(
            'WaitingRoomBloc',
            'Error logging join room failed',
            logError,
            isWarning: true,
          );
        }
      }
    } catch (e) {
      logBridgeError('WaitingRoomBloc', 'Error joining room', e);

      if (e is BridgeError_ApiResponse) {
        Sentry.captureException(
          e,
          withScope: (scope) {
            scope.setTag('connection_phase', 'waiting_room');
            scope.setContexts('connection_details', {
              'prejoin_type': state.preJoinType.toString(),
              'enable_e2ee': state.args.e2ee.toString(),
              'audio_enabled': state.args.isAudioEnabled.toString(),
              'video_enabled': state.args.isVideoEnabled.toString(),
            });
          },
        );
      }
      emit(state.copyWith(isLoading: false, error: extractErrorMessage(e)));

      // Clean up room connection if it was created but connection failed
      // This prevents other users from seeing a failed participant
      if (room != null) {
        try {
          l.logger.i(
            '[WaitingRoomBloc] Cleaning up room connection due to error',
          );

          // Cancel key rotation subscriptions first
          _cancelKeyRotationSubscriptions();

          // Stop local tracks first
          try {
            await audioTrack?.stop();
          } catch (trackError) {
            l.logger.e(
              '[WaitingRoomBloc] Error stopping audio track: $trackError',
            );
          }

          try {
            await videoTrack?.stop();
          } catch (trackError) {
            l.logger.e(
              '[WaitingRoomBloc] Error stopping video track: $trackError',
            );
          }

          // Disconnect from room to ensure other participants don't see this failed participant
          try {
            await room.disconnect();
            l.logger.i('[WaitingRoomBloc] Successfully disconnected from room');
          } catch (disconnectError) {
            l.logger.e(
              '[WaitingRoomBloc] Error disconnecting from room: $disconnectError',
            );
          }

          // Dispose room
          try {
            await room.dispose();
          } catch (disposeError) {
            l.logger.e('[WaitingRoomBloc] Error disposing room: $disposeError');
          }

          // Clean up listener
          try {
            listener?.dispose();
          } catch (listenerError) {
            l.logger.e(
              '[WaitingRoomBloc] Error disposing listener: $listenerError',
            );
          }
        } catch (cleanupError) {
          l.logger.e(
            '[WaitingRoomBloc] Unexpected error during cleanup: $cleanupError',
          );
        }
      }

      // Log join room failed if feature flag is enabled
      try {
        final dataProviderManager = ManagerFactory().get<DataProviderManager>();
        if (dataProviderManager.unleashDataProvider.isMeetClientMetricsLog()) {
          final appCoreManager = ManagerFactory().get<AppCoreManager>();
          // Extract error code from exception if possible
          String? errorCode;
          if (e is Exception) {
            errorCode = e.toString();
          }
          await appCoreManager.appCore.logJoinedRoomFailed(
            errorCode: errorCode,
          );
        }
      } catch (logError) {
        l.logger.w(
          '[WaitingRoomBloc] Error logging join room failed: $logError',
        );
      }
    }
  }

  Future<void> _onSetupRoomKey(
    WaitingRoomSetupRoomKey event,
    Emitter<WaitingRoomState> emit,
  ) async {
    if (PlatformInfoChannel.isInForceUpgradeState()) {
      return;
    }
    if (state.room == null) return;
    final newRoomKey = livekitRoomKey;
    emit(state.copyWith(roomKey: newRoomKey));
    await _setupWithRoomKey(emit);
  }

  Future<void> _setupWithRoomKey(Emitter<WaitingRoomState> emit) async {
    if (state.room == null || state.roomKey == null) return;
    try {
      state.room!.localParticipant?.setMicrophoneEnabled(
        state.args.isAudioEnabled,
      );
      if (state.args.isVideoEnabled) {
        // Manually publish video track with preferred codec (vp9 by default) first and fallback to vp8 if failed
        final preferredCodec =
            state.room!.roomOptions.defaultVideoPublishOptions.videoCodec;
        final videoParameters = state
            .room!
            .roomOptions
            .defaultCameraCaptureOptions
            .params
            .dimensions;

        LocalVideoTrack? videoTrack;
        try {
          videoTrack = await LocalVideoTrackHelper.cameraTrack(
            parameters: VideoParameters(dimensions: videoParameters),
            position: state.selectedVideoPosition,
          );
          await videoTrack.start();
          videoTrack = await publishVideoTrackWithFallback(
            participant: state.room!.localParticipant!,
            initialTrack: videoTrack,
            createTrack: () async {
              return LocalVideoTrackHelper.cameraTrack(
                parameters: VideoParameters(dimensions: videoParameters),
                position: state.selectedVideoPosition,
              );
            },
            publishOptions: state.room!.roomOptions.defaultVideoPublishOptions
                .copyWith(videoCodec: preferredCodec),
          );
          // Update state with the published track
          emit(state.copyWith(videoTrack: videoTrack));
        } catch (e) {
          l.logger.e('[WaitingRoom] Failed to publish video track: $e');
          // Clean up video track if publish fails
          try {
            await videoTrack?.stop();
          } catch (stopError) {
            l.logger.e('[WaitingRoom] Error stopping video track: $stopError');
          }
          // Don't rethrow - let user join without video
        }
      }

      emit(state.copyWith(shouldNavigateToRoom: true));
    } catch (error) {
      l.logger.d('Could not connect $error');
      // Send connection error to Sentry with context
      Sentry.captureException(
        error,
        stackTrace: error is Error ? error.stackTrace : null,
        withScope: (scope) {
          scope.setTag('connection_phase', 'waiting_room');
          scope.setContexts('connection_details', {
            'prejoin_type': state.preJoinType.toString(),
            'enable_e2ee': state.args.e2ee.toString(),
            'audio_enabled': state.args.isAudioEnabled.toString(),
            'video_enabled': state.args.isVideoEnabled.toString(),
          });
        },
      );

      emit(
        state.copyWith(
          error: error.toString(),
          currentStatus: "Error connecting to room",
        ),
      );
    }
  }

  void _onNavigateToRoom(
    WaitingRoomNavigateToRoom event,
    Emitter<WaitingRoomState> emit,
  ) {
    emit(state.copyWith(shouldNavigateToRoom: false));
  }

  /// Disconnect from LiveKit room when error occurs to prevent other users from seeing failed participant
  Future<void> _onDisconnectOnError(
    WaitingRoomDisconnectOnError event,
    Emitter<WaitingRoomState> emit,
  ) async {
    final room = state.room;
    if (room == null) {
      l.logger.w('[WaitingRoomBloc] No room to disconnect');
      return;
    }

    try {
      l.logger.i('[WaitingRoomBloc] Disconnecting from room due to error');

      // Cancel key rotation subscriptions first
      _cancelKeyRotationSubscriptions();

      // Stop local tracks first
      try {
        await state.audioTrack?.stop();
      } catch (e) {
        l.logger.e('[WaitingRoomBloc] Error stopping audio track: $e');
      }

      try {
        await state.videoTrack?.stop();
      } catch (e) {
        l.logger.e('[WaitingRoomBloc] Error stopping video track: $e');
      }

      // Disconnect from room to ensure other participants don't see this failed participant
      try {
        await room.disconnect();
        l.logger.i('[WaitingRoomBloc] Successfully disconnected from room');
      } catch (e) {
        l.logger.e('[WaitingRoomBloc] Error disconnecting from room: $e');
        Sentry.captureException(
          e,
          stackTrace: e is Error ? e.stackTrace : null,
          withScope: (scope) {
            scope.setTag('room_action', 'disconnect_on_error');
            scope.setTag('action_type', 'disconnect');
            scope.setTag('source', 'waiting_room_bloc');
          },
        );
      }

      // Dispose room
      try {
        await room.dispose();
      } catch (disposeError) {
        l.logger.e('[WaitingRoomBloc] Error disposing room: $disposeError');
        Sentry.captureException(
          disposeError,
          stackTrace: disposeError is Error ? disposeError.stackTrace : null,
          withScope: (scope) {
            scope.setTag('room_action', 'disconnect_on_error');
            scope.setTag('action_type', 'dispose');
            scope.setTag('source', 'waiting_room_bloc');
          },
        );
      }

      // Clean up listener
      try {
        state.listener?.dispose();
      } catch (e) {
        l.logger.e('[WaitingRoomBloc] Error disposing listener: $e');
        Sentry.captureException(
          e,
          stackTrace: e is Error ? e.stackTrace : null,
          withScope: (scope) {
            scope.setTag('room_action', 'disconnect_on_error');
            scope.setTag('action_type', 'dispose_listener');
            scope.setTag('source', 'waiting_room_bloc');
          },
        );
      }
    } catch (e) {
      l.logger.e('[WaitingRoomBloc] Unexpected error during disconnect: $e');
      Sentry.captureException(
        e,
        stackTrace: e is Error ? e.stackTrace : null,
        withScope: (scope) {
          scope.setTag('room_action', 'disconnect_on_error');
          scope.setTag('action_type', 'unexpected_error');
          scope.setTag('source', 'waiting_room_bloc');
        },
      );
    }
  }

  @override
  Future<void> close() {
    // Cancel all key rotation subscriptions
    _cancelKeyRotationSubscriptions();
    state.listener?.dispose();
    state.room?.dispose();
    return super.close();
  }
}
