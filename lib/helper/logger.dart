import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/rust/flutter_logger.dart';
import 'package:meet/rust/logger.dart' as rust_logger;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class DebugLogger {
  DebugLogger._(this._logger);

  factory DebugLogger({
    DateTimeFormatter dateTimeFormat = DateTimeFormat.dateAndTime,
    List<LogOutput>? outputs,
    @visibleForTesting bool? showCallerDetails,
  }) {
    return DebugLogger._(
      Logger(
        printer: _DebugLogPrinter(
          dateTimeFormat: dateTimeFormat,
          showCallerDetails: showCallerDetails ?? kDebugMode,
        ),
        output: MultiOutput(outputs ?? [ConsoleOutput()]),
      ),
    );
  }

  final Logger _logger;

  void d(
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (kDebugMode) {
      _logger.d(
        message,
        time: time,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void i(
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (kDebugMode) {
      _logger.i(
        message,
        time: time,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void w(
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (kDebugMode) {
      _logger.w(
        message,
        time: time,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void e(
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (kDebugMode) {
      _logger.e(
        message,
        time: time,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void f(
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (kDebugMode) {
      _logger.f(
        message,
        time: time,
        error: error,
        stackTrace: stackTrace,
      );
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

/// One line per log with a clickable call-site location; stack traces only for errors.
class _DebugLogPrinter extends LogPrinter {
  _DebugLogPrinter({
    this.dateTimeFormat = DateTimeFormat.dateAndTime,
    this.showCallerDetails = kDebugMode,
  });

  final DateTimeFormatter dateTimeFormat;
  final bool showCallerDetails;

  static const _errorStackFrames = 8;

  static const _wrapperPathPrefixes = [
    'package:meet/helper/logger.dart',
    'package:logger/',
  ];

  static final _deviceFrame = RegExp(r'#\d+\s+(.+) \((\S+)\)');

  static final _levelTags = {
    Level.trace: '[T]',
    Level.debug: '[D]',
    Level.info: '[I]',
    Level.warning: '[W]',
    Level.error: '[E]',
    Level.fatal: '[F]',
  };

  static final _levelColors = {
    Level.trace: AnsiColor.fg(AnsiColor.grey(0.5)),
    Level.debug: const AnsiColor.none(),
    Level.info: const AnsiColor.fg(12),
    Level.warning: const AnsiColor.fg(208),
    Level.error: const AnsiColor.fg(196),
    Level.fatal: const AnsiColor.fg(199),
  };

  static final _levelEmojis = {
    Level.trace: '',
    Level.debug: '🐛',
    Level.info: '💡',
    Level.warning: '⚠️',
    Level.error: '⛔',
    Level.fatal: '👾',
  };

  @override
  List<String> log(LogEvent event) {
    final message = _stringify(event.message);
    final time = _formatTime(event.time);
    final levelTag = _levelTags[event.level] ?? '[?]';
    final emoji = _levelEmojis[event.level] ?? '';
    final caller = showCallerDetails
        ? _firstCallerLocation(event.stackTrace ?? StackTrace.current)
        : null;

    final contentLine = [
      if (time.isNotEmpty) time,
      levelTag,
      if (emoji.isNotEmpty) emoji,
      message,
    ].join(' ');

    final coloredLine = (_levelColors[event.level] ?? const AnsiColor.none())(
      contentLine,
    );

    final output = <String>[if (caller != null) '# $caller', coloredLine];

    if (event.error != null) {
      output.add('  error: ${event.error}');
      if (_errorStackFrames > 0) {
        final stack = _filteredStack(
          event.stackTrace ?? StackTrace.current,
          _errorStackFrames,
        );
        if (stack != null) {
          output.add(stack);
        }
      }
    }

    return output;
  }

  String _formatTime(DateTime time) {
    // onlyTimeAndSinceStart needs PrettyPrinter.startTime; _DebugLogPrinter has none.
    if (dateTimeFormat == DateTimeFormat.onlyTimeAndSinceStart) {
      return DateTimeFormat.dateAndTime(time);
    }
    return dateTimeFormat(time);
  }

  String? _firstCallerLocation(StackTrace stackTrace) {
    for (final rawLine in stackTrace.toString().split('\n')) {
      final frame = _parseFrame(rawLine);
      if (frame != null) {
        return frame.location;
      }
    }
    return null;
  }

  ({String method, String location})? _parseFrame(String rawLine) {
    if (rawLine.isEmpty || _isWrapperFrame(rawLine)) {
      return null;
    }

    final match = _deviceFrame.firstMatch(rawLine);
    if (match == null) {
      return null;
    }

    final method = match.group(1);
    final location = match.group(2);
    if (method == null || location == null) {
      return null;
    }

    return (method: method, location: location);
  }

  String? _filteredStack(StackTrace stackTrace, int maxFrames) {
    final lines = <String>[];

    for (final rawLine in stackTrace.toString().split('\n')) {
      final frame = _parseFrame(rawLine);
      if (frame == null) continue;

      lines.add('  #${lines.length} ${frame.method} (${frame.location})');
      if (lines.length >= maxFrames) break;
    }

    return lines.isEmpty ? null : lines.join('\n');
  }

  bool _isWrapperFrame(String line) {
    for (final prefix in _wrapperPathPrefixes) {
      if (line.contains(prefix)) {
        return true;
      }
    }
    return false;
  }

  String _stringify(dynamic message) {
    final resolved = message is Function ? message() : message;
    if (resolved is Map || resolved is Iterable) {
      try {
        return JsonEncoder.withIndent(
          '  ',
          (object) => object.toString(),
        ).convert(resolved);
      } catch (_) {
        return resolved.toString();
      }
    }
    return resolved.toString();
  }
}

var logger = DebugLogger();

var rustLogger = Logger(
  printer: _DebugLogPrinter(),
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
    logger = DebugLogger(
      outputs: [
        ConsoleOutput(),
        AdvancedFileOutput(
          path: logsPath,
          maxFileSizeKB: 10240,
          latestFileName: appLogName,
          fileNameFormatter: customFileNameFormatter,
        ),
      ],
    );
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
      flutterLayer: (kDebugMode && mobile) ? true : false,
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
