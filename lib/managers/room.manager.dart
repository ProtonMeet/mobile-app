import 'dart:async';

import 'package:livekit_client/livekit_client.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/helper/extension/proton.meet.key.extension.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/helper/seamless.key.rotation.schedular.dart';
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/rust/proton_meet/models/meet_info.dart';
import 'package:meet/rust/proton_meet/user_config_extensions.dart';

/// Configuration for room connection
class RoomConnectionConfig {
  final String meetLinkName;
  final String meetLinkPassword;
  final String displayName;
  final bool enableE2EE;
  final bool isAudioEnabled;
  LocalAudioTrack? audioTrack; // Made mutable so it can be set in callbacks
  final RoomOptions? roomOptions;
  final Function(Room)? onRoomCreated;
  final Future<LocalAudioTrack?> Function(Room)?
  onCreateAudioTrack; // Called after prepareConnection and pre-connect E2EE keys
  final Function(Room)? onKeyRotationListenerSetup;

  RoomConnectionConfig({
    required this.meetLinkName,
    required this.meetLinkPassword,
    required this.displayName,
    required this.enableE2EE,
    required this.isAudioEnabled,
    this.audioTrack,
    this.roomOptions,
    this.onRoomCreated,
    this.onCreateAudioTrack,
    this.onKeyRotationListenerSetup,
  });
}

/// Result of room connection process
class RoomConnectionResult {
  final Room room;
  final EventsListener<RoomEvent> listener;
  final FrbMeetInfo meetInfo;
  final BaseKeyProvider? keyProvider;
  final StreamSubscription<(String, BigInt)?>? keyRotationSubscription;

  RoomConnectionResult({
    required this.room,
    required this.listener,
    required this.meetInfo,
    this.keyProvider,
    this.keyRotationSubscription,
  });

  /// Cancel all subscriptions and dispose resources
  Future<void> dispose() async {
    await keyRotationSubscription?.cancel();
  }
}

/// Manager for room connection logic shared between WaitingRoomBloc and RoomBloc.
/// Lifecycle is tied to RoomBloc when used as a member.
class RoomManager {
  final AppCoreManager appCoreManager;
  StreamSubscription<(String, BigInt)?>? _keyRotationSubscription;

  RoomManager(this.appCoreManager);

  /// Dispose resources and cancel subscriptions
  Future<void> dispose() async {
    await _keyRotationSubscription?.cancel();
    _keyRotationSubscription = null;
  }

  /// Get user config for video encoding
  Future<(VideoEncoding, VideoEncoding)> getUserConfig() async {
    final userConfig = await appCoreManager.appCore.getUserConfig();
    final cameraEncoding = userConfig.cameraMaxBitrate.videoEncoding;
    final screenEncoding = userConfig.screensharingMaxBitrate.videoEncoding;
    return (cameraEncoding, screenEncoding);
  }

  /// Get feature flags for join type
  Future<(bool, bool)> getJoinTypeFlags() async {
    bool isMeetNewJoinType = true;
    bool isMeetSwitchJoinType = true;
    try {
      final dataProviderManager = ManagerFactory().get<DataProviderManager>();
      isMeetNewJoinType = dataProviderManager.unleashDataProvider
          .isMeetNewJoinType();
      isMeetSwitchJoinType = dataProviderManager.unleashDataProvider
          .isMeetSwitchJoinType();
    } catch (e) {
      l.logger.e("error getting join type flags: $e");
    }
    return (isMeetNewJoinType, isMeetSwitchJoinType);
  }

  Future<bool> getUsePsk() async {
    try {
      final dataProviderManager = ManagerFactory().get<DataProviderManager>();
      return dataProviderManager.unleashDataProvider.isMeetUsePsk();
    } catch (e) {
      l.logger.e("error getting use psk: $e");
    }
    return false;
  }

  /// Get seamless key rotation feature flag
  Future<bool> getSeamlessKeyRotationEnabled() async {
    bool isMeetSeamlessKeyRotationEnabled = false;
    try {
      final dataProviderManager = ManagerFactory().get<DataProviderManager>();
      isMeetSeamlessKeyRotationEnabled = dataProviderManager.unleashDataProvider
          .isMeetSeamlessKeyRotationEnabled();
    } catch (e) {
      l.logger.e("error getting isMeetSeamlessKeyRotationEnabled: $e");
    }
    return isMeetSeamlessKeyRotationEnabled;
  }

  /// Create E2EE key provider and options
  Future<(BaseKeyProvider, E2EEOptions)?> createE2EEOptions() async {
    if (linux) return null;

    final keyProvider = await BaseKeyProvider.create(
      keyRingSize: 256,
      // ignore: avoid_redundant_argument_values
      sharedKey: true,
      discardFrameWhenCryptorNotReady: true,
      failureTolerance: 16,
    );
    final e2eeOptions = E2EEOptions(keyProvider: keyProvider);
    return (keyProvider, e2eeOptions);
  }

  /// Setup key rotation listener for a room
  /// Returns the subscription so it can be cancelled later
  StreamSubscription<(String, BigInt)?>? setupKeyRotationListener(
    Room room,
    Room? oldRoom,
  ) {
    if (linux || room.e2eeManager == null) return null;

    final keyRotationScheduler = oldRoom != null
        ? KeyRotationScheduler(oldRoom)
        : KeyRotationScheduler(room);

    return appCoreManager.mlsGroupKeyStream.listen((groupKeyInfo) async {
      if (groupKeyInfo != null) {
        final groupKey = groupKeyInfo.$1;
        final epoch = groupKeyInfo.$2;
        final currentRoom = room;
        final keyIndex =
            currentRoom.e2eeManager?.keyProvider.getKeyIndexFromEpoch(epoch) ??
            0;
        await currentRoom.safeSetKeyWithEpoch(groupKey, epoch);

        // Check seamless key rotation flag each time (may change)
        final isMeetSeamlessKeyRotationEnabled =
            await getSeamlessKeyRotationEnabled();

        if (isMeetSeamlessKeyRotationEnabled) {
          keyRotationScheduler.schedule(epoch, groupKey);
        } else {
          await currentRoom.safeSetKeyIndex(keyIndex);
        }
      }
    });
  }

  /// Set E2EE keys before connecting
  Future<void> setPreConnectE2EEKeys(Room room) async {
    if (linux || room.e2eeManager == null) return;

    try {
      final groupKeyInfo = await appCoreManager.appCore.getGroupKey();
      final groupKey = groupKeyInfo.$1;
      final epoch = groupKeyInfo.$2;
      await room.safeSetKeyWithEpoch(groupKey, epoch);
      final keyIndex = room.e2eeManager!.keyProvider.getKeyIndexFromEpoch(
        epoch,
      );
      await room.safeSetKeyIndex(keyIndex);
    } catch (e) {
      l.logger.w('[RoomManager] Failed to set pre-connect E2EE key: $e');
    }
  }

  /// Set E2EE keys after connecting
  Future<void> setPostConnectE2EEKeys(Room room) async {
    if (linux || room.e2eeManager == null) return;

    try {
      final groupKeyInfo = await appCoreManager.appCore.getGroupKey();
      final groupKey = groupKeyInfo.$1;
      final epoch = groupKeyInfo.$2;
      await room.safeSetKeyWithEpoch(groupKey, epoch);
      final keyIndex = room.e2eeManager!.keyProvider.getKeyIndexFromEpoch(
        epoch,
      );
      await room.safeSetKeyIndex(keyIndex);
    } catch (e) {
      l.logger.w('[RoomManager] Failed to set post-connect E2EE key: $e');
    }
  }

  /// Connect to room with retry logic
  Future<void> connectRoom(
    Room room,
    String websocketUrl,
    String accessToken, {
    LocalAudioTrack? audioTrack,
    bool isAudioEnabled = false,
  }) async {
    const maxAttempts = 2;
    Object? lastConnectError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await room.connect(
          websocketUrl,
          accessToken,
          fastConnectOptions: FastConnectOptions(
            microphone: audioTrack != null
                ? TrackOption(track: audioTrack)
                : TrackOption(enabled: isAudioEnabled),
            camera: TrackOption(
              enabled: false,
            ), // Publish manually after connect
          ),
          connectOptions: ConnectOptions(
            timeouts: Timeouts(
              connection: const Duration(seconds: 20),
              debounce: const Duration(milliseconds: 200),
              publish: const Duration(seconds: 24),
              peerConnection: const Duration(seconds: 30),
              iceRestart: const Duration(seconds: 30),
              subscribe: const Duration(seconds: 24),
            ),
          ),
        );
        lastConnectError = null;
        break;
      } catch (e) {
        lastConnectError = e;
        l.logger.w(
          '[RoomManager] room.connect failed (attempt $attempt/$maxAttempts): $e',
        );
        if (attempt < maxAttempts) {
          await Future<void>.delayed(const Duration(milliseconds: 800));
        }
      }
    }

    if (lastConnectError != null) {
      throw lastConnectError;
    }
  }

  /// Complete room connection process
  Future<RoomConnectionResult> connectToRoom(
    RoomConnectionConfig config, {
    Room? oldRoom,
    reuseToken = false,
  }) async {
    // Get user config
    final (cameraEncoding, screenEncoding) = await getUserConfig();

    // Get feature flags
    final (isMeetNewJoinType, isMeetSwitchJoinType) = await getJoinTypeFlags();

    final usePsk = await getUsePsk();

    FrbMeetInfo meetInfo;
    // Join meeting
    meetInfo = await appCoreManager.appCore.joinMeeting(
      meetLinkName: config.meetLinkName,
      meetLinkPassword: config.meetLinkPassword,
      displayName: config.displayName,
      isMeetNewJoinType: isMeetNewJoinType,
      isMeetSwitchJoinType: isMeetSwitchJoinType,
      reuseToken: reuseToken,
      usePsk: usePsk,
    );

    // Update access token and websocket url, so we can reuse it for reconnection
    await appCoreManager.appCore.updateLivekitAccessTokenAndWebsocketUrl(
      accessToken: meetInfo.accessToken,
      websocketUrl: meetInfo.websocketUrl,
    );

    // Setup E2EE if needed
    BaseKeyProvider? keyProvider;
    E2EEOptions? e2eeOptions;
    if (config.enableE2EE && !linux) {
      final e2eeResult = await createE2EEOptions();
      if (e2eeResult != null) {
        keyProvider = e2eeResult.$1;
        e2eeOptions = e2eeResult.$2;
      }
    }

    // Create room
    final roomOptions =
        config.roomOptions ??
        RoomOptions(
          adaptiveStream: true,
          dynacast: true,
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
            videoEncoding: cameraEncoding,
            screenShareEncoding: screenEncoding,
          ),
          e2eeOptions: e2eeOptions,
        );

    // If roomOptions was provided but e2eeOptions needs to be updated, create new options
    final finalRoomOptions = config.roomOptions != null && e2eeOptions != null
        ? RoomOptions(
            adaptiveStream: config.roomOptions!.adaptiveStream,
            dynacast: config.roomOptions!.dynacast,
            defaultAudioPublishOptions:
                config.roomOptions!.defaultAudioPublishOptions,
            defaultCameraCaptureOptions:
                config.roomOptions!.defaultCameraCaptureOptions,
            defaultScreenShareCaptureOptions:
                config.roomOptions!.defaultScreenShareCaptureOptions,
            defaultVideoPublishOptions:
                config.roomOptions!.defaultVideoPublishOptions,
            e2eeOptions: e2eeOptions,
          )
        : roomOptions;

    final room = Room(roomOptions: finalRoomOptions);

    config.onRoomCreated?.call(room);

    // Setup key rotation listener
    StreamSubscription<(String, BigInt)?>? keyRotationSubscription;
    if (config.enableE2EE && !linux) {
      keyRotationSubscription = setupKeyRotationListener(room, oldRoom);
      config.onKeyRotationListenerSetup?.call(room);
    }

    // Create listener
    final listener = room.createListener();

    // Prepare connection
    await room.prepareConnection(meetInfo.websocketUrl, meetInfo.accessToken);

    // Setup E2EE keys before connecting (after prepareConnection)
    if (config.enableE2EE && !linux) {
      await setPreConnectE2EEKeys(room);
    }

    // Create audio track after prepareConnection and pre-connect E2EE keys if callback provided
    if (config.onCreateAudioTrack != null) {
      config.audioTrack = await config.onCreateAudioTrack!(room);
    }

    // Connect to room
    await connectRoom(
      room,
      meetInfo.websocketUrl,
      meetInfo.accessToken,
      audioTrack: config.audioTrack,
      isAudioEnabled: config.isAudioEnabled,
    );

    // Set E2EE keys after connecting
    if (config.enableE2EE && !linux) {
      await setPostConnectE2EEKeys(room);
    }

    return RoomConnectionResult(
      room: room,
      listener: listener,
      meetInfo: meetInfo,
      keyProvider: keyProvider,
      keyRotationSubscription: keyRotationSubscription,
    );
  }
}
