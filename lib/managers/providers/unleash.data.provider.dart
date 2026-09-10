import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:meet/constants/env.dart';
import 'package:meet/helper/extension/response_error.extension.dart';
import 'package:meet/helper/logger.dart';
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/managers/providers/unleash.features.dart';
import 'package:meet/managers/providers/unleash.features.merge.dart';
import 'package:meet/managers/services/force_upgrade.dart';
import 'package:meet/rust/errors.dart';
import 'package:unleash_proxy_client_flutter/storage_provider.dart';
import 'package:unleash_proxy_client_flutter/unleash_proxy_client_flutter.dart';

export 'unleash.features.dart';
export 'unleash.features.getters.dart';
export 'unleash.features.merge.dart';

class UnleashFeatureFlagsUpdated extends DataState {
  UnleashFeatureFlagsUpdated(this.revision);

  final int revision;

  @override
  List<Object?> get props => [revision];
}

class UnleashDataProvider extends DataProvider {
  /// Unleash client for feature toggles
  late final UnleashClient unleashClient;

  final AppCoreManager appCoreManager;

  /// API environment configuration
  final ApiEnv apiEnv;

  /// Periodic refresh interval in seconds (override in tests).
  final int refreshIntervalSeconds;

  /// Timer for periodic refresh
  Timer? refreshTimer;
  Future<void> _serverTimeFlagSync = Future.value();
  int _featureFlagsRevision = 0;

  /// Called after Unleash toggles refresh (`ready` / `update`). Wired by
  /// [DataProviderManager] to re-sync feature-flag-aware providers.
  Future<void> Function()? onFeatureFlagsUpdated;

  UnleashDataProvider(
    this.apiEnv,
    this.appCoreManager, {
    bool bootstrapOverride = true,
    StorageProvider? storageProvider,
    int refreshIntervalSeconds = 120,
  }) : refreshIntervalSeconds = refreshIntervalSeconds {
    final hostApiPath = apiEnv.apiPath;
    const appName = 'ProtonMeet';
    unleashClient = UnleashClient(
      url: Uri.parse('$hostApiPath/feature/v2/frontend'),
      clientKey: '-',
      appName: appName,
      refreshInterval: refreshIntervalSeconds,
      disableMetrics: true,
      disableRefresh: true,
      bootstrapOverride: bootstrapOverride,
      storageProvider: storageProvider,
      bootstrap: getDefaultToggles(),
      fetcher: (http.Request request) async {
        final response = await appCoreManager.appCore.fetchToggles();
        final body = response.body.toList();
        if (response.statusCode == 200) {
          try {
            final mergedBody = mergeTogglesWithClientDefaults(body);
            if (kDebugMode) {
              _logUnleashJson(jsonDecode(mergedBody));
            }
            return http.Response.bytes(
              utf8.encode(mergedBody),
              response.statusCode,
            );
          } catch (e, st) {
            logger.w(
              '[Unleash] Failed to merge client defaults into toggles',
              error: e,
              stackTrace: st,
            );
          }
        }
        return http.Response.bytes(body, response.statusCode);
      },
    );
    setupUnleashListeners();
  }

  /// Sets up Unleash event listeners
  void setupUnleashListeners() {
    unleashClient.on('ready', (value) {
      _notifyFeatureFlagsUpdated();
      if (unleashClient.isEnabled('MeetFirstFlag')) {
        logger.i('MeetFirstFlag is enabled');
      } else {
        logger.i('MeetFirstFlag is disabled');
      }
    });

    unleashClient.on('error', (error) {
      if (error is BridgeError_ApiResponse) {
        final response = error.field0;
        logger.e('UnleashClient Error: ${response.detailString}');
        enterForceUpgradeFromApiIfNeeded(response);
      } else {
        logger.e('UnleashClient Error: $error');
      }
    });

    unleashClient.on('initialized', (value) {
      logger.i('UnleashClient initialized: $value');
    });

    unleashClient.on('update', (value) {
      logger.i('UnleashClient update: $value');
      _notifyFeatureFlagsUpdated();
    });

    unleashClient.on('impression', (value) {
      logger.i('UnleashClient impression: $value');
    });
  }

  // debug only
  void _logUnleashJson(Object decoded) {
    try {
      if (decoded is Map<String, dynamic>) {
        final toggles = decoded['toggles'];
        if (toggles is List) {
          for (final toggle in toggles) {
            if (toggle is Map<String, dynamic>) {
              final name = toggle['name']?.toString() ?? 'unknown';
              final enabled = toggle['enabled'] == true;
              logger.i('[Unleash] toggle $name enabled=$enabled');
              if (name == 'ScheduleInAdvance') {
                logger.i('[ScheduleInAdvance] toggle $name enabled=$enabled');
              }
            }
          }
        }
      }
    } catch (e) {
      logger.w('[Unleash] Failed to format fetchToggles JSON: $e');
    }
  }

  /// Starts the Unleash client and sets up auto-refresh
  Future<void> start() async {
    await unleashClient.start();
    startPeriodicRefresh();
  }

  /// Starts periodic refresh if not already running
  void startPeriodicRefresh() {
    if (refreshTimer == null || !refreshTimer!.isActive) {
      refreshTimer = Timer.periodic(
        Duration(seconds: refreshIntervalSeconds),
        (_) => unleashClient.start(),
      );
    }
  }

  /// Cancels only the periodic refresh timer (keeps the client for reads).
  /// Used when entering force-upgrade so background fetch stops without a full [clear].
  void stopPeriodicRefresh() {
    refreshTimer?.cancel();
    refreshTimer = null;
  }

  /// Stops and cleans up resources
  @override
  Future<void> clear() async {
    unleashClient.stop();
    refreshTimer?.cancel();
    refreshTimer = null;
  }

  @override
  Future<void> reload() async {}

  /// Returns whether [feature] is enabled (including any [UnleashFeature.parent]).
  ///
  /// Checks [kUnleashLocalOverrides] first (debug-only local toggles).
  bool isFeatureEnabled(UnleashFeature feature) {
    final parent = feature.parent;
    if (parent != null && !isFeatureEnabled(parent)) {
      return false;
    }

    if (kDebugMode) {
      // still follows parent pattern for now, but can be overridden locally
      final local = kUnleashLocalOverrides[feature];
      if (local != null) return local;
    }

    return unleashClient.isEnabled(feature.toggleName);
  }

  void _notifyFeatureFlagsUpdated() {
    _syncUseCachedServerTimeFlag();
    _featureFlagsRevision++;
    emitState(UnleashFeatureFlagsUpdated(_featureFlagsRevision));
    final callback = onFeatureFlagsUpdated;
    if (callback != null) {
      unawaited(callback());
    }
  }

  void _syncUseCachedServerTimeFlag() {
    final enabled = isFeatureEnabled(UnleashFeature.meetUseCachedServerTime);
    logger.d('isMeetUseCachedServerTime: $enabled');

    _serverTimeFlagSync = _serverTimeFlagSync.then((_) async {
      try {
        await appCoreManager.setUseCachedServerTime(enabled: enabled);
      } catch (e, stackTrace) {
        logger.w(
          '[Unleash] Error syncing MeetUseCachedServerTime flag: $e',
          error: e,
          stackTrace: stackTrace,
        );
      }
    });
    unawaited(_serverTimeFlagSync);
  }
}
