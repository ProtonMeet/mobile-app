import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meet/constants/env.dart';
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/managers/providers/unleash.data.provider.dart';
import 'package:meet/managers/secure.storage/secure.storage.manager.dart';
import 'package:meet/managers/secure.storage/secure.storage.memory.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unleash_proxy_client_flutter/in_memory_storage_provider.dart';
import 'package:unleash_proxy_client_flutter/parse_stringify_toggles.dart';
import 'package:unleash_proxy_client_flutter/unleash_proxy_client_flutter.dart';

import '../../mocks/app_core.mocks.dart';
import '../../support/unleash_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UnleashFeatureFlagsUpdated', () {
    test('uses revision in equality', () {
      expect(
        UnleashFeatureFlagsUpdated(1),
        equals(UnleashFeatureFlagsUpdated(1)),
      );
      expect(
        UnleashFeatureFlagsUpdated(1),
        isNot(equals(UnleashFeatureFlagsUpdated(2))),
      );
    });
  });

  group('UnleashDataProvider', () {
    late MockAppCore mockAppCore;
    late AppCoreManager appCoreManager;

    setUpAll(() {
      SharedPreferences.setMockInitialValues({});
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
    });

    setUp(() {
      mockAppCore = MockAppCore();
      appCoreManager = AppCoreManager(
        const ApiEnv.prod(),
        SecureStorageManager(storage: SecureStorageMemory()),
      );
      appCoreManager.appCore = mockAppCore;

      when(
        mockAppCore.setUseCachedServerTime(enabled: anyNamed('enabled')),
      ).thenAnswer((_) async {});
    });

    Future<UnleashDataProvider> createStartedProvider({
      Map<String, bool> toggles = const {},
      bool bootstrapOverride = true,
    }) async {
      final provider = createUnleashTestProvider(
        appCoreManager,
        mockAppCore,
        toggles: toggles,
        bootstrapOverride: bootstrapOverride,
      );
      await provider.start();
      return provider;
    }

    test('applies bootstrap-disabled defaults before fetch completes', () {
      final provider = createUnleashTestProvider(appCoreManager, mockAppCore);

      expect(provider.isFeatureEnabled(UnleashFeature.meetVp9), isFalse);
      expect(
        provider.isFeatureEnabled(UnleashFeature.meetUseCachedServerTime),
        isFalse,
      );
    });

    group('bootstrapOverride', () {
      test('true ignores persisted storage before fetch', () async {
        final provider = createUnleashTestProvider(
          appCoreManager,
          mockAppCore,
          persistedToggles: const {'MeetWaitingRoom': true},
        );

        await waitForUnleashInit(provider);

        expect(
          provider.isFeatureEnabled(UnleashFeature.meetWaitingRoom),
          isFalse,
        );
        verifyNever(mockAppCore.fetchToggles());
      });

      test('false restores persisted storage before fetch', () async {
        final provider = createUnleashTestProvider(
          appCoreManager,
          mockAppCore,
          bootstrapOverride: false,
          persistedToggles: const {'MeetWaitingRoom': true},
        );

        await waitForUnleashInit(provider);

        expect(
          provider.isFeatureEnabled(UnleashFeature.meetWaitingRoom),
          isTrue,
        );
        verifyNever(mockAppCore.fetchToggles());
      });

      test(
        'false with empty storage falls back to bootstrap defaults',
        () async {
          final provider = createUnleashTestProvider(
            appCoreManager,
            mockAppCore,
            bootstrapOverride: false,
          );

          await waitForUnleashInit(provider);

          expect(provider.isFeatureEnabled(UnleashFeature.meetVp9), isFalse);
          expect(
            provider.isFeatureEnabled(UnleashFeature.meetUseCachedServerTime),
            isFalse,
          );
        },
      );

      test(
        'false prefers stored value over bootstrap-disabled default',
        () async {
          final provider = createUnleashTestProvider(
            appCoreManager,
            mockAppCore,
            bootstrapOverride: false,
            persistedToggles: const {'MeetVp9': true},
          );

          await waitForUnleashInit(provider);

          expect(provider.isFeatureEnabled(UnleashFeature.meetVp9), isTrue);
        },
      );

      test('true replaces persisted storage with bootstrap on init', () async {
        final storage = InMemoryStorageProvider();
        seedPersistedUnleashToggles(storage, const {'MeetWaitingRoom': true});

        final provider = createUnleashTestProvider(
          appCoreManager,
          mockAppCore,
          storageProvider: storage,
        );

        await waitForUnleashInit(provider);

        expect(
          provider.isFeatureEnabled(UnleashFeature.meetWaitingRoom),
          isFalse,
        );
        final persisted = parseToggles(
          storage.store[storageWithApp(unleashTestAppName, storageKey)]!,
        );
        expect(persisted.containsKey('MeetWaitingRoom'), isFalse);
        expect(persisted['MeetVp9']?.enabled, isFalse);
      });

      test(
        'server fetch overrides bootstrap when bootstrapOverride is true',
        () async {
          final provider = createUnleashTestProvider(
            appCoreManager,
            mockAppCore,
            toggles: const {'MeetVp9': true},
          );

          await provider.start();

          expect(provider.isFeatureEnabled(UnleashFeature.meetVp9), isTrue);
        },
      );
    });

    test('reads server toggles after start', () async {
      final provider = await createStartedProvider(
        toggles: const {
          'MeetWaitingRoom': true,
          'MeetScreenShare': false,
          'MeetAudioDenoise': true,
          'MeetAudioDenoiseRnnoise': true,
        },
      );

      expect(provider.isFeatureEnabled(UnleashFeature.meetWaitingRoom), isTrue);
      expect(
        provider.isFeatureEnabled(UnleashFeature.meetScreenShare),
        isFalse,
      );
      expect(
        provider.isFeatureEnabled(UnleashFeature.meetAudioDenoiseRnnoise),
        isTrue,
      );
    });

    test('denoise child flags require parent flag', () async {
      final provider = await createStartedProvider(
        toggles: const {
          'MeetAudioDenoise': false,
          'MeetAudioDenoiseRnnoise': true,
          'MeetAudioDenoiseDeepfilter': true,
          'MeetAudioDenoiseDtlnRs': true,
        },
      );

      expect(
        provider.isFeatureEnabled(UnleashFeature.meetAudioDenoiseRnnoise),
        isFalse,
      );
      expect(
        provider.isFeatureEnabled(UnleashFeature.meetAudioDenoiseDeepfilter),
        isFalse,
      );
      expect(
        provider.isFeatureEnabled(UnleashFeature.meetAudioDenoiseDtlnRs),
        isFalse,
      );
    });

    test('isFeatureEnabled delegates to unleash client', () async {
      final provider = await createStartedProvider(
        toggles: const {'MeetNewJoinType': true},
      );

      expect(provider.isFeatureEnabled(UnleashFeature.meetNewJoinType), isTrue);
      expect(
        provider.isFeatureEnabled(UnleashFeature.meetPictureInPicture),
        isFalse,
      );
    });

    test('isFeatureEnabled reads all toggles from unleash', () async {
      final provider = await createStartedProvider(
        toggles: const {
          'MeetSeamlessKeyRotationEnabled': true,
          'MeetNewJoinType': true,
          'MeetScreenShare': true,
          'MeetPictureInPicture': true,
          'MeetClientMetricsLog': true,
          'MeetMobileSpeakerToggle': true,
          'MeetVp9': true,
          'MeetH264': true,
          'MeetSwitchJoinType': true,
          'MeetNewSwitchJoinType': true,
          'NeedForceUpgrade': true,
          'MeetScheduleInAdvance': true,
          'MeetAutoReconnection': true,
          'MeetMobileEnableNetworkTool': true,
          'MeetAdminLowerHand': true,
          'MeetShowProtonCalendar': true,
          'MeetFeedbackOnSkip': true,
          'MeetInAppStoreReview': true,
          'MeetMultipleRecording': true,
          'MeetingRecordingNative': true,
          'MeetMobileInAppUpdate': true,
          'MeetMobileUpgradeWarning': true,
          'MeetCameraBackgroundBlur': true,
          'MeetAudioDenoise': true,
          'MeetAudioDenoiseRnnoise': true,
          'MeetAudioDenoiseDeepfilter': true,
          'MeetAudioDenoiseDtlnRs': true,
          'MeetInAppPurchase': true,
          'MeetSettingsPreview': true,
          'MeetWaitingRoom': true,
          'MeetNewChatHandling': true,
          'MeetChatThreads': true,
          'MeetUseCachedServerTime': true,
        },
      );

      for (final feature in UnleashFeature.values) {
        expect(provider.isFeatureEnabled(feature), isTrue);
      }
    });

    test('non-200 fetch response is passed through without merge', () async {
      when(
        mockAppCore.fetchToggles(),
      ).thenAnswer((_) async => unleashTestResponse(const {}, statusCode: 500));

      final provider = createUnleashTestProvider(appCoreManager, mockAppCore);
      await provider.start();

      expect(
        provider.isFeatureEnabled(UnleashFeature.meetWaitingRoom),
        isFalse,
      );
    });

    test('emits feature-flag updates and invokes callback', () async {
      final provider = createUnleashTestProvider(
        appCoreManager,
        mockAppCore,
        toggles: const {'MeetWaitingRoom': true},
      );

      final states = <DataState>[];
      provider.stream.listen(states.add);

      var callbackCount = 0;
      provider.onFeatureFlagsUpdated = () async {
        callbackCount++;
      };

      await provider.start();

      expect(states.whereType<UnleashFeatureFlagsUpdated>(), isNotEmpty);
      expect(callbackCount, greaterThan(0));
      verify(
        mockAppCore.setUseCachedServerTime(enabled: anyNamed('enabled')),
      ).called(greaterThan(0));
    });

    test('startPeriodicRefresh triggers additional fetches', () {
      fakeAsync((async) {
        final provider = createUnleashTestProvider(
          appCoreManager,
          mockAppCore,
          refreshIntervalSeconds: 5,
        );

        unawaited(provider.start());
        async.elapse(Duration.zero);

        clearInteractions(mockAppCore);
        provider.startPeriodicRefresh();
        async.elapse(const Duration(seconds: 5));

        verify(mockAppCore.fetchToggles()).called(greaterThan(0));
        unawaited(provider.clear());
      });
    });

    test('stopPeriodicRefresh cancels timer without stopping client', () {
      fakeAsync((async) {
        final provider = createUnleashTestProvider(
          appCoreManager,
          mockAppCore,
          refreshIntervalSeconds: 5,
        );

        unawaited(provider.start());
        async.elapse(Duration.zero);

        provider.startPeriodicRefresh();
        provider.stopPeriodicRefresh();
        clearInteractions(mockAppCore);

        async.elapse(const Duration(seconds: 10));
        verifyNever(mockAppCore.fetchToggles());
      });
    });

    test('clear stops refresh timer and unleash client', () async {
      final provider = await createStartedProvider();
      expect(provider.refreshTimer, isNotNull);

      await provider.clear();

      expect(provider.refreshTimer, isNull);
    });

    test('reload is a no-op', () async {
      final provider = await createStartedProvider();
      await expectLater(provider.reload(), completes);
    });
  });
}
