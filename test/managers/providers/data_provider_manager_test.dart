import 'package:flutter_test/flutter_test.dart';
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/providers/meet.user.settings.data.provider.dart';
import 'package:meet/managers/providers/unleash.data.provider.dart';
import 'package:meet/rust/proton_meet/models/user_settings.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../mocks/app_core.mocks.dart';
import '../../support/data_provider_manager_test_support.dart';
import '../../support/unleash_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DataProviderManager', () {
    late MockAppCore mockAppCore;
    late AppCoreManager appCoreManager;

    setUpAll(() {
      SharedPreferences.setMockInitialValues({});
      registerPackageInfoChannel();
    });

    setUp(() {
      mockAppCore = MockAppCore();
      appCoreManager = createTestAppCoreManager(mockAppCore);
      when(
        mockAppCore.setUseCachedServerTime(enabled: anyNamed('enabled')),
      ).thenAnswer((_) async {});
    });

    tearDown(() async {
      await Future<void>.delayed(Duration.zero);
    });

    group('syncFromEventLoop', () {
      test('skips providers that do not need sync', () async {
        final syncable = FakeEventLoopSyncable();
        final manager = createInjectedManager(
          appCoreManager: appCoreManager,
          unleashDataProvider: StubUnleashDataProvider(),
          meetUserSettingsDataProvider: TrackingMeetUserSettingsDataProvider(
            appCoreManager,
          ),
          eventLoopSyncables: [syncable],
          featureFlagAwares: const [],
        );

        await manager.syncFromEventLoop(
          meetEvents: testEvents(),
          coreEvents: testEvents(),
        );

        expect(syncable.syncCalls, 0);
      });

      test('syncs when meet or core events require it', () async {
        final syncable = FakeEventLoopSyncable(shouldSync: true);
        final manager = createInjectedManager(
          appCoreManager: appCoreManager,
          unleashDataProvider: StubUnleashDataProvider(),
          meetUserSettingsDataProvider: TrackingMeetUserSettingsDataProvider(
            appCoreManager,
          ),
          eventLoopSyncables: [syncable],
          featureFlagAwares: const [],
        );

        await manager.syncFromEventLoop(
          meetEvents: testEvents(refresh: true),
          coreEvents: testEvents(),
        );

        expect(syncable.syncCalls, 1);
      });

      test('continues after a provider throws', () async {
        final failing = FakeEventLoopSyncable(
          shouldSync: true,
          syncError: StateError('boom'),
        );
        final succeeding = FakeEventLoopSyncable(shouldSync: true);
        final manager = createInjectedManager(
          appCoreManager: appCoreManager,
          unleashDataProvider: StubUnleashDataProvider(),
          meetUserSettingsDataProvider: TrackingMeetUserSettingsDataProvider(
            appCoreManager,
          ),
          eventLoopSyncables: [failing, succeeding],
          featureFlagAwares: const [],
        );

        await manager.syncFromEventLoop(
          meetEvents: testEvents(refresh: true),
          coreEvents: testEvents(),
        );

        expect(failing.syncCalls, 1);
        expect(succeeding.syncCalls, 1);
      });
    });

    group('syncFromFeatureFlags', () {
      test('notifies all feature-flag-aware providers', () async {
        final unleash = StubUnleashDataProvider();
        final aware = FakeFeatureFlagAware();
        final manager = createInjectedManager(
          appCoreManager: appCoreManager,
          unleashDataProvider: unleash,
          meetUserSettingsDataProvider: TrackingMeetUserSettingsDataProvider(
            appCoreManager,
          ),
          eventLoopSyncables: const [],
          featureFlagAwares: [aware],
        );

        await manager.syncFromFeatureFlags();

        expect(aware.syncCalls, 1);
        expect(aware.lastUnleash, unleash);
      });

      test('continues after a provider throws', () async {
        final failing = FakeFeatureFlagAware(syncError: StateError('boom'));
        final succeeding = FakeFeatureFlagAware();
        final manager = createInjectedManager(
          appCoreManager: appCoreManager,
          unleashDataProvider: StubUnleashDataProvider(),
          meetUserSettingsDataProvider: TrackingMeetUserSettingsDataProvider(
            appCoreManager,
          ),
          eventLoopSyncables: const [],
          featureFlagAwares: [failing, succeeding],
        );

        await manager.syncFromFeatureFlags();

        expect(failing.syncCalls, 1);
        expect(succeeding.syncCalls, 1);
      });
    });

    group('init', () {
      test(
        'creates providers and refreshes user settings for signed-in users',
        () async {
          authenticate(appCoreManager);
          when(
            mockAppCore.getUserSettings(),
          ).thenAnswer((_) async => testUserSettings);

          final manager = createProductionManager(appCoreManager);
          await manager.init();

          expect(manager.unleashDataProvider, isA<UnleashDataProvider>());
          expect(
            manager.meetUserSettingsDataProvider,
            isA<MeetUserSettingsDataProvider>(),
          );
          expect(
            manager.unleashDataProvider.onFeatureFlagsUpdated,
            manager.syncFromFeatureFlags,
          );
          verify(mockAppCore.getUserSettings()).called(1);
          expect(
            manager.meetUserSettingsDataProvider.settings,
            testUserSettings,
          );
          await shutdownManager(manager);
        },
      );

      test('clears user settings cache for guests', () async {
        final manager = createProductionManager(appCoreManager);
        await manager.init();

        verifyNever(mockAppCore.getUserSettings());
        expect(manager.meetUserSettingsDataProvider.settings, isNull);
        await shutdownManager(manager);
      });

      test('uses injected providers without recreating them', () async {
        final unleash = TrackingUnleashDataProvider(appCoreManager);
        final settings = TrackingMeetUserSettingsDataProvider(appCoreManager);
        final syncable = FakeEventLoopSyncable();
        final manager = createInjectedManager(
          appCoreManager: appCoreManager,
          unleashDataProvider: unleash,
          meetUserSettingsDataProvider: settings,
          eventLoopSyncables: [syncable],
          featureFlagAwares: const [],
        );

        await manager.init();

        expect(manager.unleashDataProvider, same(unleash));
        expect(manager.meetUserSettingsDataProvider, same(settings));
        expect(settings.refreshIfNeededCalls, 1);
        expect(unleash.startCalls, 0);
      });
    });

    group('reload', () {
      test('reloads unleash and user settings providers', () async {
        final unleash = TrackingUnleashDataProvider(appCoreManager);
        final settings = TrackingMeetUserSettingsDataProvider(appCoreManager);
        final manager = createInjectedManager(
          appCoreManager: appCoreManager,
          unleashDataProvider: unleash,
          meetUserSettingsDataProvider: settings,
          eventLoopSyncables: const [],
          featureFlagAwares: const [],
        );

        await manager.reload();

        expect(unleash.reloadCalls, 1);
        expect(settings.reloadCalls, 1);
      });
    });

    group('logout', () {
      test('clears providers and restarts unleash', () async {
        final unleash = TrackingUnleashDataProvider(appCoreManager);
        final settings = TrackingMeetUserSettingsDataProvider(appCoreManager);
        final manager = createInjectedManager(
          appCoreManager: appCoreManager,
          unleashDataProvider: unleash,
          meetUserSettingsDataProvider: settings,
          eventLoopSyncables: const [],
          featureFlagAwares: const [],
        );

        await manager.logout();

        expect(unleash.clearCalls, 1);
        expect(settings.clearCalls, 1);
        expect(unleash.startCalls, 1);
        expect(manager.unleashDataProvider, same(unleash));
      });

      test('recreates unleash on logout for production wiring', () async {
        when(
          mockAppCore.fetchToggles(),
        ).thenAnswer((_) async => unleashTestResponse(const {}));
        authenticate(appCoreManager);
        when(
          mockAppCore.getUserSettings(),
        ).thenAnswer((_) async => testUserSettings);

        final manager = createProductionManager(appCoreManager);
        await manager.init();
        final unleashBeforeLogout = manager.unleashDataProvider;

        await manager.logout();

        expect(manager.unleashDataProvider, isNot(same(unleashBeforeLogout)));
        expect(
          manager.unleashDataProvider.onFeatureFlagsUpdated,
          manager.syncFromFeatureFlags,
        );
        await shutdownManager(manager);
      });
    });

    group('login', () {
      test('recreates unleash, starts it, and reloads user settings', () async {
        when(
          mockAppCore.fetchToggles(),
        ).thenAnswer((_) async => unleashTestResponse(const {}));
        authenticate(appCoreManager);
        when(
          mockAppCore.getUserSettings(),
        ).thenAnswer((_) async => testUserSettings);

        final manager = createProductionManager(appCoreManager);
        await manager.init();
        final unleashBeforeLogin = manager.unleashDataProvider;
        clearInteractions(mockAppCore);

        when(mockAppCore.getUserSettings()).thenAnswer((_) async {
          return const FrbUserSettings(
            addressId: 'meeting-2',
            waitingRoom: false,
          );
        });

        await manager.login('user-1');

        expect(manager.unleashDataProvider, isNot(same(unleashBeforeLogin)));
        expect(
          manager.unleashDataProvider.onFeatureFlagsUpdated,
          manager.syncFromFeatureFlags,
        );
        verify(mockAppCore.getUserSettings()).called(1);
        expect(
          manager.meetUserSettingsDataProvider.settings?.addressId,
          'meeting-2',
        );
        await shutdownManager(manager);
      });

      test('clears settings before reloading on login', () async {
        when(
          mockAppCore.fetchToggles(),
        ).thenAnswer((_) async => unleashTestResponse(const {}));
        authenticate(appCoreManager);

        final settings = TrackingMeetUserSettingsDataProvider(appCoreManager);
        final manager = createInjectedManager(
          appCoreManager: appCoreManager,
          unleashDataProvider: TrackingUnleashDataProvider(appCoreManager),
          meetUserSettingsDataProvider: settings,
          eventLoopSyncables: [settings],
          featureFlagAwares: [settings],
        );
        await manager.init();

        when(
          mockAppCore.getUserSettings(),
        ).thenAnswer((_) async => testUserSettings);

        await manager.login('user-1');

        expect(settings.clearCalls, 1);
        expect(settings.reloadCalls, 1);
        await shutdownManager(manager);
      });

      test('login keeps injected unleash instance', () async {
        when(
          mockAppCore.fetchToggles(),
        ).thenAnswer((_) async => unleashTestResponse(const {}));
        authenticate(appCoreManager);

        final unleash = TrackingUnleashDataProvider(appCoreManager);
        final settings = TrackingMeetUserSettingsDataProvider(appCoreManager);
        final manager = createInjectedManager(
          appCoreManager: appCoreManager,
          unleashDataProvider: unleash,
          meetUserSettingsDataProvider: settings,
          eventLoopSyncables: [settings],
          featureFlagAwares: [settings],
        );
        await manager.init();

        when(
          mockAppCore.getUserSettings(),
        ).thenAnswer((_) async => testUserSettings);

        await manager.login('user-1');

        expect(manager.unleashDataProvider, same(unleash));
        expect(unleash.clearCalls, 1);
        expect(unleash.startCalls, 1);
        await shutdownManager(manager);
      });
    });

    group('feature flag callback wiring', () {
      test(
        'uses cached user settings on feature-flag refresh when already loaded',
        () async {
          when(mockAppCore.fetchToggles()).thenAnswer(
            (_) async => unleashTestResponse(const {'MeetWaitingRoom': true}),
          );
          authenticate(appCoreManager);
          when(
            mockAppCore.getUserSettings(),
          ).thenAnswer((_) async => testUserSettings);

          final manager = createProductionManager(appCoreManager);
          await manager.init();
          clearInteractions(mockAppCore);

          await manager.unleashDataProvider.start();
          await Future<void>.delayed(Duration.zero);

          verifyNever(mockAppCore.getUserSettings());
          await shutdownManager(manager);
        },
      );

      test(
        'skips user settings refresh when waiting room flag is disabled',
        () async {
          when(mockAppCore.fetchToggles()).thenAnswer(
            (_) async => unleashTestResponse(const {'MeetWaitingRoom': false}),
          );
          authenticate(appCoreManager);
          when(
            mockAppCore.getUserSettings(),
          ).thenAnswer((_) async => testUserSettings);

          final manager = createProductionManager(appCoreManager);
          await manager.init();
          clearInteractions(mockAppCore);

          await manager.unleashDataProvider.start();
          await Future<void>.delayed(Duration.zero);

          verifyNever(mockAppCore.getUserSettings());
          await shutdownManager(manager);
        },
      );
    });
  });
}
