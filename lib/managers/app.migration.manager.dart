import 'package:meet/constants/app.config.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/helper/logger.dart';
import 'package:meet/helper/path.helper.dart';
import 'package:meet/managers/cache/documents.cache.service.dart';
import 'package:meet/managers/manager.dart';
import 'package:meet/managers/preferences/preferences.keys.dart';
import 'package:meet/managers/preferences/preferences.manager.dart';
import 'package:meet/managers/secure.storage/secure.storage.manager.dart';

class AppMigrationManager implements Manager {
  final PreferencesManager shared;
  final SecureStorageManager secureStorage;
  final DocumentsCacheService documentsCacheService;

  AppMigrationManager(
    this.shared,
    this.secureStorage,
    this.documentsCacheService,
  );

  @override
  Future<void> dispose() async {}

  @override
  Future<void> init() async {
    /// First run logic: clear local cache from iCloud or local when app is reinstalled or app state is wrong
    await firstRun();

    /// Switching compile-time / launch config API env (prod ↔ staging ↔ atlas …): wipe caches
    /// so sessions, Hive, Rust DB, and tokens cannot leak across backends.
    await clearLocalDataIfApiEnvChanged();

    /// force rebuild drift db
    await shared.checkif(
      PreferenceKeys.appDatabaseForceVersion,
      driftDatabaseVersion,
      () async {
        // rebuild
      },
    );

    /// force rebuild rust db - clear Rust layer database files when version changes
    await shared.checkif(
      PreferenceKeys.appRustDatabaseForceVersion,
      rustDatabaseVersion,
      () async {
        // rebuild
      },
    );
  }

  /// First run logic: clears secure storage, preferences, cache files, and Rust database files
  /// when app is reinstalled or app state is wrong
  /// This ensures a clean state on first launch or when the firstTimeEntry key is missing/corrupted
  Future<void> firstRun() async {
    await shared.isFirstTimeEntry(() async {
      logger.d(
        'First run detected: clearing secure storage, preferences, cache files, and Rust database files',
      );

      // Clear secure storage (iCloud/Keychain on iOS, EncryptedSharedPreferences on Android)
      await secureStorage.deleteAll();

      // Clear preferences
      await shared.deleteAll(clearAll: true);

      // Clear cache files from documents directory (Hive, logs, SQLite)
      try {
        await documentsCacheService.clearDocumentsCache();
      } catch (e) {
        logger.w('Failed to clear documents cache files: $e');
      }
    });
  }

  Future<void> clearLocalDataIfApiEnvChanged() async {
    final current = appConfig.apiEnv.cacheIsolationKey;
    final previous = await shared.getLastApiEnvCacheKey();

    // Missing or empty: no wipe; we only persist [current] below.
    if (previous != null && previous != current) {
      logger.i(
        'API environment changed ($previous -> $current); clearing secure storage, preferences, and on-disk caches',
      );
      await secureStorage.deleteAll();
      await shared.deleteAll(clearAll: true);
      try {
        await documentsCacheService.clearDocumentsCache();
      } catch (e) {
        logger.w('Failed to clear documents cache after env switch: $e');
      }
      try {
        await deleteApplicationDatabasesFolder();
      } catch (e) {
        logger.w('Failed to clear databases folder after env switch: $e');
      }
      await shared.rebuild();
    }

    await shared.setLastApiEnvCacheKey(current);
  }

  @override
  Future<void> login(String userID) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<void> reload() async {}

  @override
  Priority getPriority() {
    return Priority.level2;
  }
}
