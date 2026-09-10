import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meet/constants/env.dart';
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/preferences/preferences.manager.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/managers/providers/event.loop.syncable.dart';
import 'package:meet/managers/providers/feature.flag.aware.dart';
import 'package:meet/managers/providers/meet.user.settings.data.provider.dart';
import 'package:meet/managers/providers/unleash.data.provider.dart';
import 'package:meet/managers/secure.storage/secure.storage.manager.dart';
import 'package:meet/managers/secure.storage/secure.storage.memory.dart';
import 'package:meet/rust/proton_meet/models/event.dart';
import 'package:meet/rust/proton_meet/models/user_settings.dart';
import 'package:mockito/mockito.dart';

import '../mocks/app_core.mocks.dart';
import '../mocks/preferences.interface.mocks.dart';

const testUserSettings = FrbUserSettings(
  addressId: 'meeting-1',
  waitingRoom: true,
);

void registerPackageInfoChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/package_info'),
        (methodCall) async {
          return {
            'appName': 'Meet',
            'packageName': 'ch.proton.meet.test',
            'version': '1.0.0',
            'buildNumber': '1',
          };
        },
      );
}

AppCoreManager createTestAppCoreManager(MockAppCore mockAppCore) {
  final manager = AppCoreManager(
    const ApiEnv.prod(),
    SecureStorageManager(storage: SecureStorageMemory()),
  );
  manager.appCore = mockAppCore;
  return manager;
}

void authenticate(AppCoreManager manager) {
  manager.userID = 'user-1';
  manager.mailboxPassword = 'password';
}

DataProviderManager createProductionManager(AppCoreManager appCoreManager) {
  return DataProviderManager(
    const ApiEnv.prod(),
    SecureStorageManager(storage: SecureStorageMemory()),
    PreferencesManager(MockPreferencesInterface()),
    appCoreManager,
  );
}

DataProviderManager createInjectedManager({
  required AppCoreManager appCoreManager,
  required UnleashDataProvider unleashDataProvider,
  required MeetUserSettingsDataProvider meetUserSettingsDataProvider,
  required List<EventLoopSyncable> eventLoopSyncables,
  required List<FeatureFlagAware> featureFlagAwares,
}) {
  return DataProviderManager(
    const ApiEnv.prod(),
    SecureStorageManager(storage: SecureStorageMemory()),
    PreferencesManager(MockPreferencesInterface()),
    appCoreManager,
    unleashDataProvider: unleashDataProvider,
    meetUserSettingsDataProvider: meetUserSettingsDataProvider,
    eventLoopSyncables: eventLoopSyncables,
    featureFlagAwares: featureFlagAwares,
  );
}

FrbGetEventsResponse testEvents({
  bool refresh = false,
  List<FrbEventItem>? users,
}) {
  return FrbGetEventsResponse(
    more: false,
    refresh: refresh,
    eventId: 'evt-1',
    users: users,
  );
}

class StubUnleashDataProvider extends Mock implements UnleashDataProvider {}

class FakeEventLoopSyncable implements EventLoopSyncable {
  FakeEventLoopSyncable({this.shouldSync = false, this.syncError});

  bool shouldSync;
  final Object? syncError;
  int syncCalls = 0;

  @override
  bool shouldSyncFromEventLoop(FrbGetEventsResponse response) => shouldSync;

  @override
  Future<void> syncFromEventLoop() async {
    syncCalls++;
    if (syncError != null) {
      throw syncError!;
    }
  }
}

class FakeFeatureFlagAware implements FeatureFlagAware {
  FakeFeatureFlagAware({this.syncError});

  final Object? syncError;
  int syncCalls = 0;
  UnleashDataProvider? lastUnleash;

  @override
  Future<void> syncFromFeatureFlags(UnleashDataProvider unleash) async {
    syncCalls++;
    lastUnleash = unleash;
    if (syncError != null) {
      throw syncError!;
    }
  }
}

/// Tracks lifecycle calls without hitting the network.
class TrackingMeetUserSettingsDataProvider
    extends MeetUserSettingsDataProvider {
  TrackingMeetUserSettingsDataProvider(AppCoreManager manager)
    : super(manager: manager);

  int refreshIfNeededCalls = 0;
  int clearCalls = 0;
  int reloadCalls = 0;

  @override
  Future<FrbUserSettings?> refreshIfNeeded() async {
    refreshIfNeededCalls++;
    return settings;
  }

  @override
  Future<void> clear() async {
    clearCalls++;
    await super.clear();
  }

  @override
  Future<void> reload() async {
    reloadCalls++;
    await refreshIfNeeded();
  }
}

/// Lightweight unleash double for lifecycle tests (no network/client startup).
class TrackingUnleashDataProvider extends UnleashDataProvider {
  TrackingUnleashDataProvider(AppCoreManager appCoreManager)
    : super(const ApiEnv.prod(), appCoreManager, refreshIntervalSeconds: 3600);

  int clearCalls = 0;
  int startCalls = 0;
  int reloadCalls = 0;

  @override
  Future<void> clear() async {
    clearCalls++;
    await super.clear();
  }

  @override
  Future<void> start() async {
    startCalls++;
  }

  @override
  Future<void> reload() async {
    reloadCalls++;
  }
}

Future<void> shutdownManager(DataProviderManager manager) async {
  manager.unleashDataProvider.onFeatureFlagsUpdated = null;
  await manager.unleashDataProvider.clear();
  await Future<void>.delayed(Duration.zero);
}
