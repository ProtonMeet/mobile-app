import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:logging/logging.dart';
import 'package:meet/constants/app.config.dart';
import 'package:meet/constants/env.var.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/helper/sentry_event_processor.dart';
import 'package:meet/permissions/register_macos_permissions.dart';
import 'package:meet/rust/frb_generated.dart';
import 'package:meet/rust/panic_hook.dart';
import 'package:meet/views/scenes/app/app.coordinator.dart';
import 'package:sentry/sentry.dart';
import 'package:timezone/data/latest_all.dart' as tz;

void initializePanicHandling() {
  // Listen to the stream of panic messages from Rust
  initializePanicHook().listen((message) {
    l.logger.e("Panic from Rust: $message");
    // Send the panic message to Sentry
    Sentry.captureMessage(message);
  });
}

Future<void> appInit() async {
  /// init everything in zone
  WidgetsFlutterBinding.ensureInitialized();
  // await LoggerService.initDartLogger();
  AppConfig.initAppEnv();
  await RustLib.init();
  await PlatformPermissionRegistry.registerPlugins();

  // Initialize timezone database
  tz.initializeTimeZones();

  hierarchicalLoggingEnabled = true;
  setLoggingLevel(LoggerLevel.kALL);

  // inital the rust panic handling
  initializePanicHandling();

  if (kDebugMode && !kIsWeb) {
    await l.LoggerService.initDartLogger();
    await l.LoggerService.initRustLogger().catchError((error) {
      l.logger.e(
        " ignore this error if it is reload or hot restart: Rust logger: $error.",
      );
    });
  }
}

void main() async {
  /// This captures errors that occur in the Flutter framework
  /// includes: Rendering Errors, Gesture Handling Errors, Build Method Errors,
  ///   Async Errors in Flutter Widgets. in case scam our sentry.
  /// we need monitor this and see if this is ok.
  FlutterError.onError = (FlutterErrorDetails details) async {
    if (kDebugMode) {
      FlutterError.dumpErrorToConsole(details);
    } else {
      // In release mode, report to Sentry
      try {
        await Sentry.captureException(
          details.exception,
          stackTrace: details.stack,
        );
      } catch (e) {
        // Log Sentry errors but don't crash the app
        l.logger.e('Failed to send error to Sentry: $e');
      }
    }
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    if (kDebugMode) {
      l.logger.e(
        "PlatformDispatcher.instance.onError: $error stacktrace: $stack",
      );
    } else {
      // In release mode, report to Sentry
      try {
        Sentry.captureException(error, stackTrace: stack);
      } catch (e) {
        // Log Sentry errors but don't crash the app
        l.logger.e('Failed to send error to Sentry: $e');
      }
    }
    return true;
  };

  /// sentry init
  await Sentry.init(
    (options) => options
      ..dsn = Env.sentryApiKey.isNotEmpty ? Env.sentryApiKey : null
      ..environment = appConfig.apiEnv.toString()
      ..debug = kDebugMode
      ..sendDefaultPii = true
      ..addEventProcessor(TagEventProcessor()),
    appRunner: () async {
      await appInit();
      final app = AppCoordinator();
      runApp(app.start());
    },
  );
}
