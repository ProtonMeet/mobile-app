import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/preferences/preferences.manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:proton_screen_recorder/proton_screen_recorder.dart';

/// Preset folders for local meeting recordings (similar to Zoom/OBS defaults).
enum RecordingSaveLocationKind { appDocuments, downloads, movies, custom }

/// User preference for where `.mp4` files are written.
class RecordingSaveLocationConfig {
  const RecordingSaveLocationConfig({required this.kind, this.customPath});

  final RecordingSaveLocationKind kind;
  final String? customPath;

  static Future<RecordingSaveLocationConfig> load([
    PreferencesManager? preferences,
  ]) async {
    final prefs = preferences ?? ManagerFactory().get<PreferencesManager>();
    final kindName =
        await prefs.getRecordingSaveLocationKindName() ??
        RecordingSaveLocationKind.appDocuments.name;
    final kind = RecordingSaveLocationKind.values.firstWhere(
      (k) => k.name == kindName,
      orElse: () => RecordingSaveLocationKind.appDocuments,
    );
    final customPath = await prefs.getRecordingSaveLocationCustomPath();
    return RecordingSaveLocationConfig(kind: kind, customPath: customPath);
  }

  Future<void> save([PreferencesManager? preferences]) async {
    final prefs = preferences ?? ManagerFactory().get<PreferencesManager>();
    await prefs.setRecordingSaveLocationKind(kind.name);
    if (kind == RecordingSaveLocationKind.custom) {
      await prefs.setRecordingSaveLocationCustomPath(customPath);
    }
  }

  /// Whether in-room settings should show "Save recordings to".
  ///
  /// iOS always writes to app Documents (export via share). Android and desktop
  /// can offer additional folders when native recording is available.
  static bool get supportsSaveLocationPicker {
    if (kIsWeb || iOS) return false;
    return availableKinds().length > 1;
  }

  /// Kinds shown in the in-room settings picker for this platform.
  static List<RecordingSaveLocationKind> availableKinds() {
    if (kIsWeb) return const [];
    if (iOS) {
      // Sandbox only — no user-facing folder choice on iPhone/iPad.
      return const [RecordingSaveLocationKind.appDocuments];
    }
    if (macOS) {
      return const [
        RecordingSaveLocationKind.appDocuments,
        RecordingSaveLocationKind.downloads,
        RecordingSaveLocationKind.movies,
        RecordingSaveLocationKind.custom,
      ];
    }
    if (windows || linux) {
      return const [
        RecordingSaveLocationKind.appDocuments,
        RecordingSaveLocationKind.downloads,
        RecordingSaveLocationKind.custom,
      ];
    }
    if (android) {
      // App-private storage or public Downloads/Proton Meet.
      return const [
        RecordingSaveLocationKind.appDocuments,
        RecordingSaveLocationKind.downloads,
      ];
    }
    return const [RecordingSaveLocationKind.appDocuments];
  }

  String labelKey() {
    switch (kind) {
      case RecordingSaveLocationKind.appDocuments:
        return 'recording_save_location_app_documents';
      case RecordingSaveLocationKind.downloads:
        return 'recording_save_location_downloads';
      case RecordingSaveLocationKind.movies:
        return 'recording_save_location_movies';
      case RecordingSaveLocationKind.custom:
        return 'recording_save_location_custom';
    }
  }

  /// Resolves the folder where video files are created (`recording-*.mp4`).
  Future<Directory> resolveVideoDirectory() async {
    Directory base;
    switch (kind) {
      case RecordingSaveLocationKind.appDocuments:
        final docs = await getApplicationDocumentsDirectory();
        base = Directory(p.join(docs.path, 'recordings'));
      case RecordingSaveLocationKind.downloads:
        if (android) {
          // Android scoped storage: capture in app storage, then publish to
          // public Downloads when the recording completes.
          final docs = await getApplicationDocumentsDirectory();
          base = Directory(p.join(docs.path, 'recordings'));
        } else {
          final downloads = await getDownloadsDirectory();
          if (downloads == null) {
            throw StateError('Downloads folder is unavailable on this device');
          }
          base = Directory(p.join(downloads.path, 'Proton Meet'));
        }
      case RecordingSaveLocationKind.movies:
        final home = Platform.environment['HOME'];
        if (home == null || home.isEmpty) {
          throw StateError('Home folder is unavailable');
        }
        base = Directory(p.join(home, 'Movies', 'Proton Meet'));
      case RecordingSaveLocationKind.custom:
        final path = customPath?.trim();
        if (path == null || path.isEmpty) {
          return RecordingSaveLocationConfig(
            kind: RecordingSaveLocationKind.appDocuments,
          ).resolveVideoDirectory();
        }
        base = Directory(path);
    }

    if (!base.existsSync()) {
      await base.create(recursive: true);
    }
    return base;
  }

  Future<String> displayPath() async {
    try {
      if (android && kind == RecordingSaveLocationKind.downloads) {
        return '/storage/emulated/0/Download/Proton Meet';
      }
      final dir = await resolveVideoDirectory();
      return dir.path;
    } catch (e) {
      l.logger.w('[RecordingSaveLocation] displayPath failed: $e');
      return '';
    }
  }

  /// Android only: copy a finished recording to public Downloads/Proton Meet.
  static Future<String?> publishToPublicDownloadsIfNeeded(
    String sourcePath, {
    ProtonScreenRecorder? screenRecorder,
  }) async {
    if (kIsWeb || !android) return null;
    final config = await load();
    if (config.kind != RecordingSaveLocationKind.downloads) return null;

    final file = File(sourcePath);
    if (!file.existsSync()) return null;

    final recorder = screenRecorder ?? ProtonScreenRecorder();
    return recorder.publishToDownloads(
      sourcePath: sourcePath,
      displayName: p.basename(sourcePath),
    );
  }

  static Future<String?> pickCustomDirectory() async {
    if (kIsWeb) return null;
    return getDirectoryPath(confirmButtonText: 'Select');
  }
}
