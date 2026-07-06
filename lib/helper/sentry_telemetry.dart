import 'package:meet/helper/logger.dart';
import 'package:meet/managers/app.core.manager.dart';

/// Gates Sentry uploads on Proton account `UserSettings.Telemetry` (`GET /core/v4/settings`).
///
/// The settings API returns many `UserSettings` fields; Meet only fetches and uses
/// `Telemetry` today. Guest sessions are not subject to this check.
class SentryTelemetry {
  static final SentryTelemetry _instance = SentryTelemetry._internal();

  factory SentryTelemetry() => _instance;

  SentryTelemetry._internal();

  bool _requiresTelemetryConsent = false;
  bool _telemetryEnabled = false;
  bool _initialized = false;

  bool get canSendToSentry {
    if (!_requiresTelemetryConsent) {
      return true;
    }
    if (!_initialized) {
      return false;
    }
    return _telemetryEnabled;
  }

  void resetForGuest() {
    _requiresTelemetryConsent = false;
    _telemetryEnabled = false;
    _initialized = true;
  }

  /// Fetches `/core/v4/settings` for signed-in users; no-op for guests.
  Future<void> refreshIfNeeded(AppCoreManager manager) async {
    if (!manager.isAuthenticated) {
      resetForGuest();
      return;
    }

    _requiresTelemetryConsent = true;
    _initialized = false;
    try {
      _telemetryEnabled = await manager.appCore.getProtonTelemetryEnabled();
      _initialized = true;
      logger.i('Proton telemetry setting loaded: enabled=$_telemetryEnabled');
    } catch (e, st) {
      logger.w(
        'Failed to load Proton telemetry setting; blocking Sentry',
        error: e,
        stackTrace: st,
      );
      _telemetryEnabled = false;
      _initialized = true;
    }
  }
}
