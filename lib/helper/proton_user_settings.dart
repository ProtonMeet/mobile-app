import 'package:meet/helper/logger.dart';
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/rust/proton_meet/models/user_settings.dart';

/// Caches the signed-in user's Meet user settings (`GET/PUT /meet/v1/user-settings`).
class ProtonUserSettings {
  static final ProtonUserSettings instance = ProtonUserSettings._();

  ProtonUserSettings._();

  FrbUserSettings? _settings;

  FrbUserSettings? get settings => _settings;

  bool get defaultWaitingRoomEnabled => _settings?.waitingRoom ?? false;

  void resetForGuest() {
    _settings = null;
  }

  /// Returns cached settings or fetches from the server when missing.
  Future<FrbUserSettings?> ensureLoaded(AppCoreManager manager) async {
    if (_settings != null) {
      return _settings;
    }
    return refreshIfNeeded(manager);
  }

  /// Convenience for flows that only need the waiting-room default.
  Future<bool> resolveWaitingRoomDefault(AppCoreManager manager) async {
    await ensureLoaded(manager);
    return defaultWaitingRoomEnabled;
  }

  /// Loads settings for signed-in users; clears cache for guests.
  Future<FrbUserSettings?> refreshIfNeeded(AppCoreManager manager) async {
    if (!manager.isAuthenticated) {
      resetForGuest();
      return null;
    }

    try {
      _settings = await manager.appCore.getUserSettings();
      logger.i(
        'Proton user settings loaded: waitingRoom=${_settings!.waitingRoom}',
      );
      return _settings;
    } catch (e, st) {
      logger.w('Failed to load Proton user settings', error: e, stackTrace: st);
      return _settings;
    }
  }

  Future<FrbUserSettings> updateWaitingRoom(
    AppCoreManager manager, {
    required bool enable,
  }) async {
    _settings = await manager.appCore.updateUserSettingsWaitingRoom(
      enable: enable,
    );
    return _settings!;
  }
}
