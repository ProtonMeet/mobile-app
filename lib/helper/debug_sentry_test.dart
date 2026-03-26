import 'package:flutter/foundation.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:sentry/sentry.dart';

/// Creates a comprehensive Sentry event example
/// Debug only - for testing Sentry integration
SentryEvent createEventExample() {
  return SentryEvent(
    message: SentryMessage('Complete event example from Proton Meet App'),
    level: SentryLevel.warning,
    logger: 'proton-meet',
    platform: 'dart',
    timestamp: DateTime.now(),
  );
}

/// Test function to verify Sentry integration
/// Sends comprehensive test events including breadcrumbs, user context, tags, and exceptions
/// Debug only - this function does nothing in release mode
Future<void> testSentryIntegration() async {
  if (!kDebugMode) {
    return;
  }

  try {
    l.logger.i('\nReporting a complete event example:');

    // Add breadcrumb for user authentication
    Sentry.addBreadcrumb(
      Breadcrumb(
        message: 'Authenticated user',
        category: 'auth',
        type: 'debug',
        data: {
          'admin': true,
          'permissions': [1, 2, 3],
        },
      ),
    );

    // Configure scope with user context, tags, and extras
    await Sentry.configureScope((scope) async {
      await scope.setUser(
        SentryUser(
          id: '800',
          username: 'test-user',
          email: 'test@proton.meet',
          data: <String, String>{'first-sign-in': '2024-01-01'},
        ),
      );
      scope
        ..transaction = '/example/app/1'
        ..level = SentryLevel.warning;
      await scope.setTag('build', '579');
      await scope.setTag('test', 'true');
      await scope.setContexts('company-name', 'Proton Technologies');
      await scope.setContexts('app-name', 'Proton Meet');
    });

    // Send a full Sentry event payload
    try {
      final event = createEventExample();
      final sentryId = await Sentry.captureEvent(event);
      l.logger.i('Capture event result: SentryId: $sentryId');
    } catch (e) {
      l.logger.e('Failed to capture event: $e');
    }

    // Send a test message
    l.logger.i('\nCapture message:');
    try {
      final messageSentryId = await Sentry.captureMessage(
        'Test message from Proton Meet App - 2',
        level: SentryLevel.warning,
        template: 'Message %s',
        params: ['1'],
      );
      l.logger.i('Capture message result: SentryId: $messageSentryId');
    } catch (e) {
      l.logger.e('Failed to capture message: $e');
    }

    // Test exception with stack trace
    try {
      await loadConfig();
    } catch (error, stackTrace) {
      l.logger.i('\nReporting the following stack trace:');
      l.logger.i(stackTrace.toString());
      try {
        final sentryId = await Sentry.captureException(
          error,
          stackTrace: stackTrace,
          withScope: (scope) {
            scope.setTag('test', 'true');
            scope.setTag('test_type', 'exception');
          },
        );
        l.logger.i('Capture exception result: SentryId: $sentryId');
      } catch (e) {
        l.logger.e('Failed to capture exception: $e');
      }
    }

    // Test unhandled error (will be caught by runZonedGuarded)
    l.logger.i('\nTesting unhandled error (will be caught by zone):');
    await loadConfig();

    l.logger.i('\nTest Sentry events sent successfully');
  } catch (e) {
    l.logger.e('Error sending test Sentry events: $e');
  }
}

/// Helper functions to create a stack trace for testing
/// Debug only - for testing Sentry integration
Future<void> loadConfig() async {
  if (!kDebugMode) {
    return;
  }
  await parseConfig();
}

/// Debug only - for testing Sentry integration
Future<void> parseConfig() async {
  if (!kDebugMode) {
    return;
  }
  await decode();
}

/// Debug only - for testing Sentry integration
Future<void> decode() async {
  if (!kDebugMode) {
    return;
  }
  throw StateError('This is a test error for Sentry integration');
}
