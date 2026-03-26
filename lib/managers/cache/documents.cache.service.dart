import 'dart:io';

import 'package:meet/constants/constants.dart';
import 'package:meet/helper/logger.dart';
import 'package:meet/managers/manager.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Service to manage cache files in the documents directory
/// This includes Hive files, log files, and SQLite files
class DocumentsCacheService implements Manager {
  DocumentsCacheService();

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> login(String userID) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<void> reload() async {}

  @override
  Priority getPriority() {
    return Priority.level3;
  }

  /// Clears all cache files from the documents directory and its subfolders
  /// This includes:
  /// - Hive database files (.hive, .lock)
  /// - Log files (.log) and logs directory
  /// - SQLite files (.sqlite, .sqlite-journal, .sqlite-wal, .sqlite-shm)
  /// Note: Files in the "databases" subfolder are handled by RustStorageHelper
  Future<void> clearDocumentsCache() async {
    try {
      final appDocumentsDir = await getApplicationDocumentsDirectory();
      final dir = Directory(appDocumentsDir.path);

      if (!dir.existsSync()) {
        logger.d('Documents directory does not exist: ${appDocumentsDir.path}');
        return;
      }

      int deletedCount = 0;
      final databasesPath = path.join(appDocumentsDir.path, 'databases');
      final logsPath = path.join(appDocumentsDir.path, 'logs');

      // First, delete the logs directory entirely if it exists
      final logsDir = Directory(logsPath);
      if (logsDir.existsSync()) {
        try {
          await logsDir.delete(recursive: true);
          deletedCount++;
          logger.i('Deleted logs directory: $logsPath');
        } catch (e) {
          logger.e('Failed to delete logs directory $logsPath: $e');
        }
      }

      // Then, recursively scan and delete cache files in all subfolders
      final List<FileSystemEntity> entities = dir.listSync(recursive: true);
      final Set<String> processedPaths = {};

      for (FileSystemEntity entity in entities) {
        // Skip if already processed (logs directory was already deleted)
        if (processedPaths.contains(entity.path)) {
          continue;
        }

        // Skip databases folder entirely (handled by RustStorageHelper)
        if (entity.path.startsWith(databasesPath)) {
          continue;
        }

        if (entity is File) {
          final String fileName = path.basename(entity.path);
          final String fileExtension = path.extension(fileName).toLowerCase();
          bool shouldDelete = false;

          final fileCheck = "$hiveFilesName$fileExtension";
          // Delete Hive database files
          if ((fileExtension == '.hive' || fileExtension == '.lock') &&
              fileName != fileCheck) {
            shouldDelete = true;
          }
          // Delete log files (in case any remain outside logs directory)
          if (fileExtension == '.log' || fileName.contains('.log.')) {
            shouldDelete = true;
          }
          // Delete SQLite database files (if not in databases subfolder)
          if (fileExtension == '.sqlite' ||
              fileExtension == '.sqlite-journal' ||
              fileExtension == '.sqlite-wal' ||
              fileExtension == '.sqlite-shm') {
            shouldDelete = true;
          }

          if (shouldDelete) {
            try {
              await entity.delete();
              deletedCount++;
              logger.i('Deleted cache file: ${entity.path}');
            } catch (e) {
              logger.e('Failed to delete file ${entity.path}: $e');
            }
          }
        }
      }

      // Clean up empty subdirectories (except databases)
      await _cleanupEmptySubdirectories(appDocumentsDir.path, databasesPath);

      logger.i(
        'Cleared documents cache: deleted $deletedCount files/directories',
      );
    } catch (e) {
      logger.e('Error clearing documents cache: $e');
      rethrow;
    }
  }

  /// Recursively removes empty subdirectories, excluding the databases folder
  Future<void> _cleanupEmptySubdirectories(
    String rootPath,
    String excludePath,
  ) async {
    try {
      final rootDir = Directory(rootPath);
      if (!rootDir.existsSync()) {
        return;
      }

      // Get all subdirectories
      final List<Directory> subdirs = [];
      await for (FileSystemEntity entity in rootDir.list(recursive: true)) {
        if (entity is Directory && entity.path != excludePath) {
          subdirs.add(entity);
        }
      }

      // Sort by depth (deepest first) so we can delete nested empty dirs
      subdirs.sort(
        (a, b) => b.path
            .split(path.separator)
            .length
            .compareTo(a.path.split(path.separator).length),
      );

      for (final subdir in subdirs) {
        // Skip if path is within excluded path
        if (subdir.path.startsWith(excludePath)) {
          continue;
        }

        try {
          final contents = subdir.listSync();
          if (contents.isEmpty) {
            await subdir.delete();
            logger.d('Deleted empty directory: ${subdir.path}');
          }
        } catch (e) {
          // Directory might have been deleted already or have permission issues
          logger.d('Could not check/delete directory ${subdir.path}: $e');
        }
      }
    } catch (e) {
      logger.w('Error cleaning up empty subdirectories: $e');
    }
  }

  /// Clears Hive database files specifically from documents directory and all subfolders
  Future<void> clearHiveFiles() async {
    try {
      final appDocumentsDir = await getApplicationDocumentsDirectory();
      final dir = Directory(appDocumentsDir.path);

      if (!dir.existsSync()) {
        logger.d('Documents directory does not exist: ${appDocumentsDir.path}');
        return;
      }

      final List<FileSystemEntity> entities = dir.listSync(recursive: true);
      int deletedCount = 0;

      for (FileSystemEntity entity in entities) {
        if (entity is File) {
          final String fileExtension = path
              .extension(entity.path)
              .toLowerCase();
          if (fileExtension == '.hive' || fileExtension == '.lock') {
            try {
              await entity.delete();
              deletedCount++;
              logger.i('Deleted Hive file: ${entity.path}');
            } catch (e) {
              logger.e('Failed to delete Hive file ${entity.path}: $e');
            }
          }
        }
      }

      logger.i('Cleared Hive files: deleted $deletedCount files');
    } catch (e) {
      logger.e('Error clearing Hive files: $e');
      rethrow;
    }
  }

  /// Clears log files specifically from documents directory and all subfolders
  /// This includes the logs directory and any .log files in other locations
  Future<void> clearLogFiles() async {
    try {
      final appDocumentsDir = await getApplicationDocumentsDirectory();
      final dir = Directory(appDocumentsDir.path);

      if (!dir.existsSync()) {
        logger.d('Documents directory does not exist: ${appDocumentsDir.path}');
        return;
      }

      int deletedCount = 0;
      final logsPath = path.join(appDocumentsDir.path, 'logs');

      // Delete the logs directory entirely if it exists
      final logsDir = Directory(logsPath);
      if (logsDir.existsSync()) {
        try {
          await logsDir.delete(recursive: true);
          deletedCount++;
          logger.i('Deleted logs directory: $logsPath');
        } catch (e) {
          logger.e('Failed to delete logs directory $logsPath: $e');
        }
      }

      // Also delete any .log files in other locations
      final List<FileSystemEntity> entities = dir.listSync(recursive: true);
      for (FileSystemEntity entity in entities) {
        if (entity is File) {
          // Skip files in logs directory (already deleted)
          if (entity.path.startsWith(logsPath)) {
            continue;
          }

          final String fileName = path.basename(entity.path);
          final String fileExtension = path.extension(fileName).toLowerCase();
          if (fileExtension == '.log' || fileName.contains('.log.')) {
            try {
              await entity.delete();
              deletedCount++;
              logger.i('Deleted log file: ${entity.path}');
            } catch (e) {
              logger.e('Failed to delete log file ${entity.path}: $e');
            }
          }
        }
      }

      logger.i('Cleared log files: deleted $deletedCount files/directories');
    } catch (e) {
      logger.e('Error clearing log files: $e');
      rethrow;
    }
  }
}
