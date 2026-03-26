import 'dart:async';
import 'dart:math';

import 'package:livekit_client/livekit_client.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/rust/proton_meet/token.dart';
import 'package:meet/views/scenes/prejoin/prejoin_state.dart';

class SimulationService {
  String _generateRandomId() {
    final random = Random.secure();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(
      8,
      (index) => chars[random.nextInt(chars.length)],
    ).join();
  }

  static final SimulationService _instance = SimulationService._internal();
  factory SimulationService() => _instance;
  SimulationService._internal();

  final List<Room> _simulatedRooms = [];
  LocalVideoTrack? _mockVideoTrack;

  Future<void> addRoom({
    required String displayName,
    required String roomID,
    bool enableVideo = true,
    bool enableAudio = true,
    bool enableE2EE = true,
  }) async {
    final secret = "";
    // Env.livekitApiSecret;
    final apiKey = "";
    // Env.livekitApiKey;
    final url = "";
    final identity = _generateRandomId();
    final token = createToken(
      apiKey: apiKey,
      apiSecret: secret,
      identity: identity,
      name: displayName,
      room: roomID,
    );

    final cameraEncoding = const VideoEncoding(
      maxBitrate: 5 * 1000 * 1000,
      maxFramerate: 30,
    );

    final screenEncoding = const VideoEncoding(
      maxBitrate: 3 * 1000 * 1000,
      maxFramerate: 15,
    );
    BaseKeyProvider? keyProvider;
    keyProvider = await BaseKeyProvider.create(
      discardFrameWhenCryptorNotReady: true,
    );
    final e2eeOptions = E2EEOptions(keyProvider: keyProvider);
    keyProvider.setKey(livekitRoomKey, keyIndex: 0);
    final room = Room(
      roomOptions: RoomOptions(
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
          params: VideoParameters(dimensions: VideoDimensionsPresets.h1080_169),
        ),
        defaultVideoPublishOptions: VideoPublishOptions(
          videoCodec: VideoCodec.vp8.name,
          backupVideoCodec: BackupVideoCodec(),
          videoEncoding: cameraEncoding,
          screenShareEncoding: screenEncoding,
        ),
        e2eeOptions: e2eeOptions,
      ),
    );

    await room.prepareConnection(url, token);

    LocalAudioTrack? audioTrack;
    LocalVideoTrack? videoTrack;

    if (enableVideo) {
      _mockVideoTrack ??= await LocalVideoTrack.createCameraTrack(
        CameraCaptureOptions(
          params: VideoParameters(dimensions: VideoDimensions(1280, 720)),
        ),
      );
      videoTrack = _mockVideoTrack;
      if (videoTrack != null && !videoTrack.isActive) {
        await videoTrack.start();
      }
    }

    await room.connect(
      url,
      token,
      fastConnectOptions: FastConnectOptions(
        microphone: TrackOption(track: audioTrack),
        camera: TrackOption(track: videoTrack),
      ),
      connectOptions: const ConnectOptions(),
    );

    // Set up local participant
    final localParticipant = room.localParticipant;
    if (localParticipant != null) {
      localParticipant.setName(displayName);
      // if (enableVideo) {
      //   await localParticipant.setCameraEnabled(false);
      // }
      // if (enableAudio) {
      //   await localParticipant.setMicrophoneEnabled(false);
      // }
    }
    _simulatedRooms.add(room);
  }

  List<Room> get simulatedRooms => List.unmodifiable(_simulatedRooms);

  Future<void> closeAllRooms() async {
    await _mockVideoTrack?.dispose();
    _mockVideoTrack = null;
    for (final room in _simulatedRooms) {
      await room.disconnect();
    }
    _simulatedRooms.clear();
  }

  Future<void> removeParticipant({
    required String roomID,
    required String participantName,
  }) async {
    // Find the room that contains this participant
    final room = _simulatedRooms.firstWhere(
      (room) => room.name == roomID,
      orElse: () => throw Exception('Room not found'),
    );

    // Disconnect the room
    await room.disconnect();

    // Remove the room from the list
    _simulatedRooms.remove(room);

    if (_mockVideoTrack != null) {
      await _mockVideoTrack?.start();
    }
  }
}
