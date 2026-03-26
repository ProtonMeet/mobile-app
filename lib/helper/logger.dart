import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:meet/rust/flutter_logger.dart';
import 'package:meet/rust/logger.dart' as rust_logger;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class DebugLogger {
  final Logger _logger;

  DebugLogger(this._logger);

  void d(
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (kDebugMode) {
      _logger.d(message, time: time, error: error, stackTrace: stackTrace);
    }
  }

  void i(
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (kDebugMode) {
      _logger.i(message, time: time, error: error, stackTrace: stackTrace);
    }
  }

  void w(
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (kDebugMode) {
      _logger.w(message, time: time, error: error, stackTrace: stackTrace);
    }
  }

  void e(
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (kDebugMode) {
      _logger.e(message, time: time, error: error, stackTrace: stackTrace);
    }
  }

  void f(
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (kDebugMode) {
      _logger.f(message, time: time, error: error, stackTrace: stackTrace);
    }
  }

  void log(
    Level level,
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (kDebugMode) {
      _logger.log(
        level,
        message,
        time: time,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}

final _baseLogger = Logger(
  printer: PrettyPrinter(
    methodCount: 1,
    dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
  ),
  output: MultiOutput([ConsoleOutput()]),
);

var logger = DebugLogger(_baseLogger);

var rustLogger = Logger(
  printer: PrettyPrinter(
    methodCount: 1,
    // Don't set printTime when using dateTimeFormat
    dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
  ),
  output: MultiOutput([ConsoleOutput()]),
);

/// Rules:
///   mobile  10mb /logfile.  100mb max
///   desktop 30mb / logfile 300mb max
class LoggerService {
  LoggerService();

  static String appLogName = "app_logs.log";
  static String rustLogName = "app_rust_logs.log";

  static String customFileNameFormatter(DateTime timestamp) {
    final formattedTimestamp = DateFormat('yyyyMMddHHmmss').format(timestamp);
    return 'app_logs_$formattedTimestamp.log';
  }

  static Future<void> initDartLogger() async {
    final directory = await getApplicationDocumentsDirectory();
    final logsPath = join(directory.path, "logs");
    final baseLogger = Logger(
      printer: PrettyPrinter(
        methodCount: 1,
        dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
      ),
      output: MultiOutput([
        ConsoleOutput(),
        AdvancedFileOutput(
          path: logsPath,
          maxFileSizeKB: 10240,
          latestFileName: appLogName,
          fileNameFormatter: customFileNameFormatter,
        ),
      ]),
    );
    logger = DebugLogger(baseLogger);
  }

  static Future<void> initRustLogger() async {
    /// if enable rust_logger then we need to disable frb_logger
    final directory = await getApplicationDocumentsDirectory();
    final logsDir = join(directory.path, "logs");

    setFlutterLogCallback(
      callback: (RustLevel level, String message) async {
        if (kDebugMode) {
          rustLogger.i('[RUST] $level - $message');
        }
      },
    );

    rust_logger.initRustLogging(
      filePath: logsDir,
      fileName: 'app_rust_logs.log',
      flutterLayer: kDebugMode ? true : false,
    );
  }

  static Future<String> getLogsSize() async {
    int totalSize = 0;
    final directory = await getApplicationDocumentsDirectory();
    final logsPath = join(directory.path, "logs");
    final folder = Directory(logsPath);
    // Use recursive iteration to get all file sizes
    if (folder.existsSync()) {
      await for (FileSystemEntity entity in folder.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
    }
    return _formatBytes(totalSize);
  }

  /// Function to format bytes into a human-readable string
  static String _formatBytes(int bytes, [int decimals = 2]) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final i = (log(bytes) / log(1024)).floor();
    final size = bytes / pow(1024, i);
    return '${size.toStringAsFixed(decimals)} ${suffixes[i]}';
  }

  static Future<void> clearLogs() async {
    final exceptFiles = [appLogName, rustLogName];
    final directory = await getApplicationDocumentsDirectory();
    final logsPath = join(directory.path, "logs");
    final folder = Directory(logsPath);

    if (folder.existsSync()) {
      final files = folder.listSync();

      for (final file in files) {
        if (file is File && !exceptFiles.contains(file.path.split('/').last)) {
          try {
            await file.delete();
            if (kDebugMode) {
              logger.i('${file.path} deleted');
            }
          } catch (e) {
            if (kDebugMode) {
              logger.i('Error deleting ${file.path}: $e');
            }
          }
        }
      }
      if (kDebugMode) {
        logger.i('Folder cleared except for ${exceptFiles.join(", ")}');
      }
    } else {
      if (kDebugMode) {
        logger.i('Directory does not exist');
      }
    }
  }
}
