import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:meet/helper/logger.dart';

class _CapturingLogOutput extends LogOutput {
  final lines = <String>[];

  @override
  void output(OutputEvent event) {
    lines.addAll(event.lines);
  }
}

void main() {
  group('DebugLogger', () {
    test('prints meta and message on one line', () {
      final output = _CapturingLogOutput();
      final debugLogger = DebugLogger(outputs: [output]);

      debugLogger.d('isMeetUseCachedServerTime: false');

      final contentLine = output.lines.last;
      expect(
        output.lines.where((line) => !line.startsWith('# ')),
        hasLength(1),
      );
      expect(contentLine, contains('[D]'));
      expect(contentLine, contains('🐛'));
      expect(contentLine, contains('isMeetUseCachedServerTime: false'));
    });

    test('prints call site first and message on the next line', () {
      final output = _CapturingLogOutput();
      final debugLogger = DebugLogger(outputs: [output]);

      debugLogger.i('[Unleash] toggle MeetVp9 enabled=false');

      expect(output.lines, hasLength(2));
      expect(output.lines[0], startsWith('# '));
      expect(output.lines[0], contains('debug_logger_test.dart:'));
      expect(output.lines[1], contains('[I]'));
      expect(output.lines[1], contains('💡'));
      expect(
        output.lines[1],
        contains('[Unleash] toggle MeetVp9 enabled=false'),
      );
    });

    test('prints error logs with filtered stack trace', () {
      final output = _CapturingLogOutput();
      final debugLogger = DebugLogger(outputs: [output]);

      debugLogger.e(
        'Failed to merge toggles',
        error: StateError('bad state'),
        stackTrace: StackTrace.fromString('''
#0      DebugLogger.e (package:meet/helper/logger.dart:58:15)
#1      UnleashDataProvider.start (package:meet/managers/providers/unleash.data.provider.dart:158:20)
#2      main (file:///test.dart:10:5)
'''),
      );

      expect(
        output.lines.any((line) => line.contains('Failed to merge toggles')),
        isTrue,
      );
      expect(output.lines.any((line) => line.contains('error:')), isTrue);
      expect(
        output.lines.any((line) => line.contains('unleash.data.provider.dart')),
        isTrue,
      );
      expect(
        output.lines.any((line) => line.contains('helper/logger.dart')),
        isFalse,
      );
    });

    test(
      'onlyTimeAndSinceStart falls back without PrettyPrinter.startTime',
      () {
        final output = _CapturingLogOutput();
        final debugLogger = DebugLogger(
          outputs: [output],
          dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
        );

        expect(() => debugLogger.e('startup failed'), returnsNormally);
        expect(
          output.lines.any((line) => line.contains('startup failed')),
          isTrue,
        );
      },
    );
  });

  group('DebugLogger release mode', () {
    test('omits only the caller path line', () {
      final output = _CapturingLogOutput();
      final debugLogger = DebugLogger(
        outputs: [output],
        showCallerDetails: false,
      );

      debugLogger.i('[Unleash] toggle MeetVp9 enabled=false');

      expect(output.lines, hasLength(1));
      expect(output.lines.single, isNot(startsWith('# ')));
      expect(
        output.lines.single,
        contains('[Unleash] toggle MeetVp9 enabled=false'),
      );
      expect(output.lines.single, contains('[I]'));
      expect(output.lines.single, contains('💡'));
    });

    test('keeps error text and stack trace without caller path', () {
      final output = _CapturingLogOutput();
      final debugLogger = DebugLogger(
        outputs: [output],
        showCallerDetails: false,
      );

      debugLogger.e(
        'Failed to merge toggles',
        error: StateError('bad state'),
        stackTrace: StackTrace.fromString('''
#0      DebugLogger.e (package:meet/helper/logger.dart:58:15)
#1      UnleashDataProvider.start (package:meet/managers/providers/unleash.data.provider.dart:158:20)
'''),
      );

      expect(output.lines.any((line) => line.startsWith('# ')), isFalse);
      expect(
        output.lines.any((line) => line.contains('Failed to merge toggles')),
        isTrue,
      );
      expect(output.lines.any((line) => line.contains('error:')), isTrue);
      expect(
        output.lines.any((line) => line.contains('unleash.data.provider.dart')),
        isTrue,
      );
      expect(
        output.lines.any((line) => line.contains('helper/logger.dart')),
        isFalse,
      );
    });
  });
}
