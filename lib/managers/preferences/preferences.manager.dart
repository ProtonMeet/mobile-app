import 'package:meet/constants/constants.dart';
import 'package:meet/helper/extension/strings.dart';
import 'package:meet/helper/logger.dart';
import 'package:meet/managers/manager.dart';
import 'package:meet/managers/preferences/limited_display_preferences.dart';
import 'package:meet/managers/preferences/preferences.interface.dart';
import 'package:meet/managers/preferences/preferences.keys.dart';

typedef Logic = Future<void> Function();

class PreferencesManager implements Manager {
  // storage interface
  final PreferencesInterface storage;
  final firstTimeEntryKey = "firstTimeEntry";
  final LimitedDisplayPreferences limitedDisplayPreferences;

  PreferencesManager(this.storage)
    : limitedDisplayPreferences = LimitedDisplayPreferences(storage);

  /// function
  Future<void> deleteAll({required bool clearAll}) async {
    await storage.deleteAll(clearAll: clearAll);
    await rebuild();
  }

  Future<void> delete(String key) async {
    await storage.delete(key);
  }

  Map toMap() {
    return storage.toMap();
  }

  Future<void> rebuild() async {
    await storage.write(firstTimeEntryKey, false);

    /// Mark database versions to the correct version
    /// since we already call appMigrationManager.init(); in app.viewmodel.dart
    await storage.write(
      PreferenceKeys.appDatabaseForceVersion,
      driftDatabaseVersion,
    );
    await storage.write(
      PreferenceKeys.appRustDatabaseForceVersion,
      rustDatabaseVersion,
    );
  }

  Future<void> isFirstTimeEntry(Logic run) async {
    await checkif(firstTimeEntryKey, false, run);
  }

  /// Non-empty value from last cold start; `null` if missing or blank (treated like first use).
  Future<String?> getLastApiEnvCacheKey() async {
    final v = await storage.read(PreferenceKeys.lastApiEnvCacheKey);
    if (v is! String || v.isEmpty) return null;
    return v;
  }

  Future<void> setLastApiEnvCacheKey(String value) async {
    await storage.write(PreferenceKeys.lastApiEnvCacheKey, value);
  }

  Future<void> checkif(String key, dynamic value, Logic run) async {
    // Get the value
    final dynamic checkValue = await storage.read(key);
    // Check if the value is false
    if (checkValue != value) {
      logger.d('Running logic because checkValue $key is not match');
      await run.call();
      await storage.write(key, value);
    }
  }

  // Future<dynamic> read(String key) async {
  //   return storage.read(key);
  // }

  // Future<void> write(String key, dynamic value) async {
  //   await storage.write(key, value);
  // }

  @override
  Future<void> dispose() async {}

  @override
  Future<void> init() async {}

  @override
  Future<void> logout() async {
    await deleteAll(clearAll: false);
  }

  @override
  Future<void> login(String userID) async {}

  // ========================== Start of Display Name Methods ==========================
  // Display name storage keys
  static const String _displayNameKey = 'proton.meet.displayName';
  static const String _keepDisplayNameKey = 'proton.meet.keepDisplayName';

  String _getDisplayNameKey({required bool isGuest, String? userId}) {
    return _displayNameKey;
  }

  String _getKeepDisplayNameKey({required bool isGuest, String? userId}) {
    return _keepDisplayNameKey;
  }

  Future<void> saveDisplayName({
    required String displayName,
    required bool isGuest,
    String? userId,
  }) async {
    final sanitized = displayName.sanitize();

    if (sanitized == null || sanitized.isEmpty) return;

    final key = _getDisplayNameKey(isGuest: isGuest, userId: userId);
    await storage.write(key, sanitized);
  }

  Future<String?> getDisplayName({
    required bool isGuest,
    String? userId,
  }) async {
    final key = _getDisplayNameKey(isGuest: isGuest, userId: userId);
    final value = await storage.read(key);
    try {
      return value as String?;
    } catch (e) {
      logger.e("error getting display name: $e");
      return null;
    }
  }

  Future<void> clearDisplayName({required bool isGuest, String? userId}) async {
    final key = _getDisplayNameKey(isGuest: isGuest, userId: userId);
    await storage.delete(key);
  }

  Future<void> saveKeepDisplayNamePreference({
    required bool keep,
    required bool isGuest,
    String? userId,
  }) async {
    final key = _getKeepDisplayNameKey(isGuest: isGuest, userId: userId);
    await storage.write(key, keep);
  }

  Future<bool> getKeepDisplayNamePreference({
    required bool isGuest,
    String? userId,
  }) async {
    final key = _getKeepDisplayNameKey(isGuest: isGuest, userId: userId);
    final value = await storage.read(key);
    return value as bool? ?? true; // default to true from the design
  }

  Future<void> clearAllDisplayNameData({
    required bool isGuest,
    String? userId,
  }) async {
    final displayNameKey = _getDisplayNameKey(isGuest: isGuest, userId: userId);
    final keepKey = _getKeepDisplayNameKey(isGuest: isGuest, userId: userId);

    await storage.delete(displayNameKey);
    await storage.delete(keepKey);
  }

  // ========================== End of Display Name Methods ==========================

  @override
  Future<void> reload() async {}

  @override
  Priority getPriority() {
    return Priority.level1;
  }
}
