// recording_storage.dart
//
// Persists local recording sessions under app Documents so in-progress files
// survive crashes. Video files are written to the user-selected folder when
// [RecordingSaveLocationConfig] is configured; session manifest stays in app
// Documents for recovery bookkeeping.
import 'dart:convert';
import 'dart:io';

import 'package:meet/helper/logger.dart' as l;
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/preferences/preferences.manager.dart';
import 'package:meet/views/scenes/room/recording/recording_save_location.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Lifecycle state tracked in [RecordingStorage].
enum RecordingSessionStatus {
  inProgress,
  completed,

  /// Session was in-progress when the app last exited; fragmented MP4 may be
  /// playable up to the last complete fragment.
  recovered,
  failed,
}

/// Metadata for one local recording attempt.
class RecordingSession {
  const RecordingSession({
    required this.id,
    required this.filePath,
    required this.startedAtMs,
    required this.status,
    this.roomName,
    this.completedAtMs,
  });

  final String id;
  final String filePath;
  final String? roomName;
  final int startedAtMs;
  final RecordingSessionStatus status;
  final int? completedAtMs;

  bool get isRecoverable =>
      status == RecordingSessionStatus.inProgress ||
      status == RecordingSessionStatus.recovered;

  Map<String, dynamic> toJson() => {
    'id': id,
    'filePath': filePath,
    if (roomName != null) 'roomName': roomName,
    'startedAtMs': startedAtMs,
    'status': status.name,
    if (completedAtMs != null) 'completedAtMs': completedAtMs,
  };

  factory RecordingSession.fromJson(Map<String, dynamic> json) {
    return RecordingSession(
      id: json['id'] as String,
      filePath: json['filePath'] as String,
      roomName: json['roomName'] as String?,
      startedAtMs: json['startedAtMs'] as int,
      status: RecordingSessionStatus.values.byName(json['status'] as String),
      completedAtMs: json['completedAtMs'] as int?,
    );
  }

  RecordingSession copyWith({
    RecordingSessionStatus? status,
    int? completedAtMs,
  }) {
    return RecordingSession(
      id: id,
      filePath: filePath,
      roomName: roomName,
      startedAtMs: startedAtMs,
      status: status ?? this.status,
      completedAtMs: completedAtMs ?? this.completedAtMs,
    );
  }
}

/// Manages the on-disk recordings folder and session manifest.
class RecordingStorage {
  RecordingStorage({PreferencesManager? preferences})
    : _preferences = preferences;

  static const _manifestFolderName = 'recordings';
  static const _manifestFileName = 'sessions.json';

  final PreferencesManager? _preferences;
  List<RecordingSession>? _cachedSessions;

  PreferencesManager get _prefs =>
      _preferences ?? ManagerFactory().get<PreferencesManager>();

  /// App-private folder for session manifest (not user-facing video path).
  Future<Directory> _manifestDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _manifestFolderName));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Folder where new `.mp4` files are created (user preference).
  Future<Directory> videoOutputDirectory() async {
    final config = await RecordingSaveLocationConfig.load(_prefs);
    return config.resolveVideoDirectory();
  }

  Future<File> _manifestFile() async {
    final dir = await _manifestDirectory();
    return File(p.join(dir.path, _manifestFileName));
  }

  /// Creates a unique output path for a new recording.
  Future<String> createOutputPath({String extension = 'mp4'}) async {
    final dir = await videoOutputDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return p.join(dir.path, 'recording-$timestamp.$extension');
  }

  Future<List<RecordingSession>> listSessions() async {
    if (_cachedSessions != null) return _cachedSessions!;

    final file = await _manifestFile();
    if (!file.existsSync()) {
      _cachedSessions = [];
      return _cachedSessions!;
    }

    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw) as List<dynamic>;
      _cachedSessions = decoded
          .map((e) => RecordingSession.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      l.logger.w('[RecordingStorage] failed to read manifest: $e');
      _cachedSessions = [];
    }
    return _cachedSessions!;
  }

  Future<void> _persistSessions(List<RecordingSession> sessions) async {
    _cachedSessions = List.unmodifiable(sessions);
    final file = await _manifestFile();
    await file.writeAsString(
      jsonEncode(sessions.map((s) => s.toJson()).toList()),
    );
  }

  Future<RecordingSession> markSessionStarted({
    required String sessionId,
    required String filePath,
    String? roomName,
  }) async {
    final sessions = await listSessions();
    final session = RecordingSession(
      id: sessionId,
      filePath: filePath,
      roomName: roomName,
      startedAtMs: DateTime.now().millisecondsSinceEpoch,
      status: RecordingSessionStatus.inProgress,
    );
    await _persistSessions([...sessions, session]);
    return session;
  }

  Future<void> markSessionCompleted(String sessionId) async {
    final sessions = await listSessions();
    final updated = sessions
        .map(
          (s) => s.id == sessionId
              ? s.copyWith(
                  status: RecordingSessionStatus.completed,
                  completedAtMs: DateTime.now().millisecondsSinceEpoch,
                )
              : s,
        )
        .toList();
    await _persistSessions(updated);
  }

  Future<void> markSessionFailed(String sessionId) async {
    final sessions = await listSessions();
    final updated = sessions
        .map(
          (s) => s.id == sessionId
              ? s.copyWith(status: RecordingSessionStatus.failed)
              : s,
        )
        .toList();
    await _persistSessions(updated);
  }

  /// Sessions left in-progress after a crash, with a non-empty file on disk.
  Future<List<RecordingSession>> findRecoverableSessions() async {
    final sessions = await listSessions();
    final recoverable = <RecordingSession>[];

    for (final session in sessions) {
      if (session.status != RecordingSessionStatus.inProgress) continue;
      final file = File(session.filePath);
      if (file.existsSync() && file.lengthSync() > 0) {
        recoverable.add(session);
      }
    }
    return recoverable;
  }

  /// Syncs manifest state with `.mp4` files on disk.
  ///
  /// Call on app launch and before showing [listSavedRecordings], so crash
  /// orphans and stop failures with a partial file still appear in the UI.
  Future<List<RecordingSession>> reconcileAll() async {
    _cachedSessions = null;
    await reconcileOrphanedSessions();
    await reconcileDiskImports();
    return listSavedRecordings();
  }

  /// Picks up orphan `.mp4` files and promotes [failed] entries when the file
  /// still exists. Public so room init can run it without reloading the list.
  Future<void> reconcileDiskImports() async {
    await _importOrphanMp4Files();
  }

  /// Marks orphaned in-progress sessions as [recovered] when a file exists.
  Future<List<RecordingSession>> reconcileOrphanedSessions() async {
    final sessions = await listSessions();
    final recovered = <RecordingSession>[];
    var changed = false;

    final updated = sessions.map((session) {
      if (session.status != RecordingSessionStatus.inProgress) {
        return session;
      }
      final file = File(session.filePath);
      if (file.existsSync() && file.lengthSync() > 0) {
        changed = true;
        final next = session.copyWith(
          status: RecordingSessionStatus.recovered,
          completedAtMs: DateTime.now().millisecondsSinceEpoch,
        );
        recovered.add(next);
        return next;
      }
      changed = true;
      return session.copyWith(status: RecordingSessionStatus.failed);
    }).toList();

    if (changed) {
      await _persistSessions(updated);
    }
    return recovered;
  }

  /// Picks up `.mp4` files on disk that are missing from the manifest, and
  /// promotes [failed] entries when the file still exists.
  Future<void> _importOrphanMp4Files() async {
    final dir = await videoOutputDirectory();
    if (!dir.existsSync()) return;

    final sessions = await listSessions();
    final byPath = {for (final session in sessions) session.filePath: session};
    var changed = false;
    final updated = List<RecordingSession>.from(sessions);
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is! File) continue;
      if (!entity.path.toLowerCase().endsWith('.mp4')) continue;
      if (entity.lengthSync() <= 0) continue;

      final path = entity.path;
      final existing = byPath[path];
      if (existing != null) {
        if (existing.status == RecordingSessionStatus.failed) {
          final index = updated.indexWhere((s) => s.filePath == path);
          if (index >= 0) {
            updated[index] = existing.copyWith(
              status: RecordingSessionStatus.recovered,
              completedAtMs: existing.completedAtMs ?? now,
            );
            changed = true;
          }
        }
        continue;
      }

      final modifiedMs = entity.lastModifiedSync().millisecondsSinceEpoch;
      updated.add(
        RecordingSession(
          id: 'disk-${p.basenameWithoutExtension(path)}',
          filePath: path,
          startedAtMs: modifiedMs,
          status: RecordingSessionStatus.recovered,
          completedAtMs: modifiedMs,
        ),
      );
      changed = true;
      l.logger.i('[RecordingStorage] imported orphan recording: $path');
    }

    if (changed) {
      await _persistSessions(updated);
    }
  }

  /// Completed and recovered sessions with existing files, newest first.
  Future<List<RecordingSession>> listSavedRecordings() async {
    final sessions = await listSessions();
    final saved = sessions.where((s) {
      if (s.status != RecordingSessionStatus.completed &&
          s.status != RecordingSessionStatus.recovered) {
        return false;
      }
      final file = File(s.filePath);
      return file.existsSync() && file.lengthSync() > 0;
    }).toList();
    saved.sort((a, b) => b.startedAtMs.compareTo(a.startedAtMs));
    return saved;
  }
}
