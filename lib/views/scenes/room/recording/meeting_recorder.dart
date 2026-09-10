// meeting_recorder.dart
//
// Orchestrates local screen recording for the meeting host/admin. Mirrors the
// web `useMeetingRecorder` hook: starts capture, publishes MLS-encrypted
// recording status to peers, and keeps bloc state in sync.
//
// Recordings use fragmented MP4 (native `movieFragmentInterval`) so partial
// files remain playable if the app crashes before stop/finishWriting.
import 'dart:async';
import 'dart:io';

import 'package:livekit_client/livekit_client.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/notification_service.dart';
import 'package:meet/views/scenes/room/message_topic.dart';
import 'package:meet/views/scenes/room/recording/recording_save_location.dart';
import 'package:meet/views/scenes/room/recording/recording_storage.dart';
import 'package:meet/views/scenes/room/room_bloc.dart';
import 'package:meet/views/scenes/room/room_event.dart';
import 'package:proton_screen_recorder/proton_screen_recorder.dart';

typedef PublishRecordingStatus =
    Future<void> Function(
      RecordingStatus status, {
      String? targetParticipantIdentity,
    });

typedef RecordingErrorHandler = void Function(String message);

typedef RecordingInterruptedHandler = void Function();

/// Called when orphaned in-progress sessions are found on init (e.g. after crash).
typedef RecoverableRecordingsHandler =
    void Function(List<RecordingSession> sessions);

/// Local meeting recorder — one instance per active [RoomPage].
class MeetingRecorder {
  MeetingRecorder({
    required this.room,
    required this.bloc,
    required this.publishRecordingStatus,
    required this.onError,
    this.onRecoverableRecordings,
    this.onRecordingInterrupted,
    ProtonScreenRecorder? screenRecorder,
    RecordingStorage? recordingStorage,
  }) : _screenRecorder = screenRecorder ?? ProtonScreenRecorder(),
       _storage = recordingStorage ?? RecordingStorage();

  final Room room;
  final RoomBloc bloc;
  final PublishRecordingStatus publishRecordingStatus;
  final RecordingErrorHandler onError;
  final RecoverableRecordingsHandler? onRecoverableRecordings;
  final RecordingInterruptedHandler? onRecordingInterrupted;

  final ProtonScreenRecorder _screenRecorder;
  final RecordingStorage _storage;

  StreamSubscription<ScreenRecorderEvent>? _eventSubscription;
  EventsListener<RoomEvent>? _roomListener;
  String? _recordingIdentity;
  String? _sessionId;
  String? _outputPath;
  bool _isActive = false;
  bool _isFinishing = false;

  bool get isActive => _isActive;

  /// Most recent completed output path from this recorder instance.
  String? get lastSavedPath => _lastSavedPath;
  String? _lastSavedPath;

  bool get _blocShowsLocalRecording {
    final identity = room.localParticipant?.identity;
    return identity != null && bloc.state.isParticipantRecording(identity);
  }

  Future<bool> isSupported() => _screenRecorder.isSupported();

  Future<void> init() async {
    _eventSubscription = _screenRecorder.events().listen(_onNativeEvent);
    _roomListener = room.createListener(synchronized: true)
      ..on<ParticipantConnectedEvent>((event) {
        if (_isActive) {
          unawaited(
            publishRecordingStatus(
              RecordingStatus.started,
              targetParticipantIdentity: event.participant.identity,
            ),
          );
        }
      })
      ..on<RoomReconnectedEvent>((_) => _rebindIdentityAfterReconnect());

    await _checkForRecoverableRecordings();
  }

  Future<void> _checkForRecoverableRecordings() async {
    try {
      final recovered = await _storage.reconcileOrphanedSessions();
      await _storage.reconcileDiskImports();
      if (recovered.isNotEmpty) {
        l.logger.i(
          '[MeetingRecorder] found ${recovered.length} recoverable recording(s)',
        );
        onRecoverableRecordings?.call(recovered);
      }
    } catch (e) {
      l.logger.w('[MeetingRecorder] recovery check failed: $e');
    }
  }

  Future<void> dispose() async {
    if (_isActive) {
      await finishRecording(notifyPeers: false);
    }
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _roomListener?.dispose();
    _roomListener = null;
  }

  Future<void> startRecording() async {
    if (_isActive) return;

    if (!await _screenRecorder.isSupported()) {
      throw const ScreenRecordingNotSupportedException();
    }

    _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    _outputPath = await _storage.createOutputPath();
    await _storage.markSessionStarted(
      sessionId: _sessionId!,
      filePath: _outputPath!,
      roomName: room.name,
    );

    if (android) {
      final prepared = await _prepareAndroidRecording();
      if (!prepared) {
        await _storage.markSessionFailed(_sessionId!);
        _sessionId = null;
        _outputPath = null;
        throw Exception(
          'Recording requires notification and screen capture permissions',
        );
      }
    }

    try {
      await _screenRecorder.startRecording(outputPath: _outputPath);
    } catch (e) {
      if (android) {
        await _releaseAndroidRecordingFgs();
      }
      await _storage.markSessionFailed(_sessionId!);
      _sessionId = null;
      _outputPath = null;
      rethrow;
    }
    _isActive = true;

    final identity = room.localParticipant?.identity;
    if (identity != null) {
      _recordingIdentity = identity;
      bloc.add(ParticipantRecordingStarted(identity: identity));
      bloc.add(const StartLocalRecordingTimer());
    }

    await publishRecordingStatus(RecordingStatus.started);
  }

  /// Stops capture and notifies peers. File-based capture returns a saved path.
  Future<String?> finishRecording({bool notifyPeers = true}) async {
    if (_isFinishing) return _lastSavedPath;

    final wasNativeActive = _isActive;
    final wasBlocActive = _blocShowsLocalRecording;
    if (!wasNativeActive && !wasBlocActive) return _lastSavedPath;

    _isFinishing = true;
    String? savedPath;
    try {
      final nativeStillRecording = await _screenRecorder.isRecording();
      if (nativeStillRecording) {
        savedPath = await _screenRecorder.stopRecording();
      } else if (wasNativeActive) {
        savedPath = _resolveSavedPathAfterNativeStop();
      }
      if (savedPath != null && savedPath.isNotEmpty) {
        _lastSavedPath = savedPath;
        if (android) {
          final published =
              await RecordingSaveLocationConfig.publishToPublicDownloadsIfNeeded(
                savedPath,
                screenRecorder: _screenRecorder,
              );
          if (published != null) {
            l.logger.i(
              '[MeetingRecorder] published recording to Downloads: $published',
            );
          }
        }
      }
      if (notifyPeers && (wasNativeActive || wasBlocActive)) {
        await publishRecordingStatus(RecordingStatus.stopped);
      }
    } catch (e) {
      l.logger.e('[MeetingRecorder] stop failed: $e');
      if (_sessionId != null) {
        await _storage.markSessionFailed(_sessionId!);
      }
      onError(_recordingErrorMessage(e, fallback: 'Failed to stop recording'));
    } finally {
      if (android) {
        await _releaseAndroidRecordingFgs();
      }
      final sessionId = _sessionId;
      if (sessionId != null && savedPath != null && savedPath.isNotEmpty) {
        await _storage.markSessionCompleted(sessionId);
      }
      _markStopped();
      _isFinishing = false;
    }
    return savedPath ?? _lastSavedPath;
  }

  /// Reconcile UI when ReplayKit stopped capture (e.g. app was backgrounded).
  Future<void> syncNativeRecordingState() async {
    if (_isFinishing || (!_isActive && !_blocShowsLocalRecording)) {
      return;
    }

    final nativeStillRecording = await _screenRecorder.isRecording();
    if (!nativeStillRecording && (_isActive || _blocShowsLocalRecording)) {
      l.logger.w(
        '[MeetingRecorder] native capture inactive while UI still recording',
      );
      await _handleRecordingInterrupted();
    }
  }

  String? _resolveSavedPathAfterNativeStop() {
    final path = _outputPath ?? _lastSavedPath;
    if (path == null) return null;
    final file = File(path);
    if (file.existsSync() && file.lengthSync() > 0) {
      return path;
    }
    return null;
  }

  Future<void> _handleRecordingInterrupted() async {
    await finishRecording();
    onRecordingInterrupted?.call();
  }

  void _markStopped() {
    _isActive = false;
    _sessionId = null;
    _outputPath = null;

    final identities = <String>{};
    final trackedIdentity = _recordingIdentity;
    if (trackedIdentity != null) {
      identities.add(trackedIdentity);
    }
    final localIdentity = room.localParticipant?.identity;
    if (localIdentity != null) {
      identities.add(localIdentity);
    }

    for (final identity in identities) {
      if (bloc.state.isParticipantRecording(identity)) {
        bloc.add(ParticipantRecordingStopped(identity: identity));
      }
    }

    bloc.add(const StopLocalRecordingTimer());
    _recordingIdentity = null;
  }

  void _onNativeEvent(ScreenRecorderEvent event) {
    if (_isFinishing) {
      return;
    }

    switch (event) {
      case ScreenRecorderEvent.interrupted:
        l.logger.i('[MeetingRecorder] recording interrupted by system');
        unawaited(_handleRecordingInterrupted());
      case ScreenRecorderEvent.stopped:
        if (_isActive || _blocShowsLocalRecording) {
          l.logger.i('[MeetingRecorder] native recording stopped');
          unawaited(finishRecording());
        }
      case ScreenRecorderEvent.availabilityChanged:
        break;
    }
  }

  /// Android 14+ requires a mediaProjection foreground service before capture.
  Future<bool> _prepareAndroidRecording() async {
    if (!android) return true;
    try {
      final notificationService = ManagerFactory().get<NotificationService>();
      final roomName = (room.name ?? '').trim();
      return await notificationService.startScreenShareForegroundService(
        roomName: roomName.isNotEmpty ? roomName : 'Meeting',
      );
    } catch (e) {
      l.logger.w('[MeetingRecorder] Android FGS prep failed: $e');
      return false;
    }
  }

  Future<void> _releaseAndroidRecordingFgs() async {
    if (!android) return;
    if (room.localParticipant?.isScreenShareEnabled() == true) {
      return;
    }
    try {
      final notificationService = ManagerFactory().get<NotificationService>();
      final roomName = (room.name ?? '').trim();
      await notificationService.stopScreenShareForegroundService(
        roomName: roomName.isNotEmpty ? roomName : 'Meeting',
      );
    } catch (e) {
      l.logger.w('[MeetingRecorder] Android FGS release failed: $e');
    }
  }

  static String _recordingErrorMessage(
    Object error, {
    required String fallback,
  }) {
    final message = switch (error) {
      ScreenRecordingNotSupportedException(:final message) =>
        message ?? fallback,
      _ => error.toString(),
    };

    const prefix = 'Exception: ';
    var normalized = message.startsWith(prefix)
        ? message.substring(prefix.length)
        : message;

    for (final marker in [
      'Failed to stop recording: ',
      'Failed to start recording: ',
    ]) {
      final index = normalized.indexOf(marker);
      if (index >= 0) {
        normalized = normalized.substring(index + marker.length);
        break;
      }
    }

    return normalized.isNotEmpty ? normalized : fallback;
  }

  void _rebindIdentityAfterReconnect() {
    if (!_isActive) return;

    final newIdentity = room.localParticipant?.identity;
    final previousIdentity = _recordingIdentity;
    if (newIdentity == null ||
        previousIdentity == null ||
        newIdentity == previousIdentity) {
      return;
    }

    bloc.add(ParticipantRecordingStopped(identity: previousIdentity));
    bloc.add(ParticipantRecordingStarted(identity: newIdentity));
    _recordingIdentity = newIdentity;

    unawaited(publishRecordingStatus(RecordingStatus.started));
  }
}
