import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meet/constants/env.dart';
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/providers/unleash.data.provider.dart';
import 'package:meet/managers/secure.storage/secure.storage.manager.dart';
import 'package:meet/managers/secure.storage/secure.storage.memory.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../mocks/app_core.mocks.dart';
import '../../support/unleash_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Each getter must read the matching Unleash toggle name.
  final getterCases = <(bool Function(UnleashDataProvider), String)>[
    (
      (p) => p.isMeetSeamlessKeyRotationEnabled(),
      'MeetSeamlessKeyRotationEnabled',
    ),
    ((p) => p.isMeetUseCachedServerTime(), 'MeetUseCachedServerTime'),
    ((p) => p.isMeetNewJoinType(), 'MeetNewJoinType'),
    ((p) => p.isMeetScreenShare(), 'MeetScreenShare'),
    ((p) => p.isMeetPictureInPicture(), 'MeetPictureInPicture'),
    ((p) => p.isMeetClientMetricsLog(), 'MeetClientMetricsLog'),
    ((p) => p.isMeetMobileSpeakerToggle(), 'MeetMobileSpeakerToggle'),
    ((p) => p.isMeetVp9(), 'MeetVp9'),
    ((p) => p.isMeetH264(), 'MeetH264'),
    ((p) => p.isMeetSwitchJoinType(), 'MeetSwitchJoinType'),
    ((p) => p.isMeetNewSwitchJoinType(), 'MeetNewSwitchJoinType'),
    ((p) => p.isNeedForceUpgrade(), 'NeedForceUpgrade'),
    ((p) => p.isMeetScheduleInAdvance(), 'MeetScheduleInAdvance'),
    ((p) => p.isMeetAutoReconnection(), 'MeetAutoReconnection'),
    ((p) => p.isMeetMobileEnableNetworkTool(), 'MeetMobileEnableNetworkTool'),
    ((p) => p.isMeetAdminLowerHand(), 'MeetAdminLowerHand'),
    ((p) => p.isMeetShowProtonCalendar(), 'MeetShowProtonCalendar'),
    ((p) => p.isMeetFeedbackOnSkip(), 'MeetFeedbackOnSkip'),
    ((p) => p.isMeetInAppStoreReviewEnabled(), 'MeetInAppStoreReview'),
    ((p) => p.isMeetMultipleRecording(), 'MeetMultipleRecording'),
    ((p) => p.isMeetMeetingRecordingNative(), 'MeetingRecordingNative'),
    ((p) => p.isMeetInAppPurchaseEnabled(), 'MeetInAppPurchase'),
    ((p) => p.isMeetCameraBackgroundBlur(), 'MeetCameraBackgroundBlur'),
    ((p) => p.isMeetMobileInAppUpdate(), 'MeetMobileInAppUpdate'),
    ((p) => p.isMeetMobileUpgradeWarning(), 'MeetMobileUpgradeWarning'),
    ((p) => p.isMeetAudioDenoise(), 'MeetAudioDenoise'),
    ((p) => p.isMeetAudioDenoiseRnnoise(), 'MeetAudioDenoiseRnnoise'),
    ((p) => p.isMeetAudioDenoiseDeepfilter(), 'MeetAudioDenoiseDeepfilter'),
    ((p) => p.isMeetAudioDenoiseDtlnRs(), 'MeetAudioDenoiseDtlnRs'),
    ((p) => p.isMeetWaitingRoom(), 'MeetWaitingRoom'),
    ((p) => p.isMeetNewChatHandling(), 'MeetNewChatHandling'),
    ((p) => p.isMeetChatThreads(), 'MeetChatThreads'),
    ((p) => p.isMeetSettingsPreview(), 'MeetSettingsPreview'),
  ];

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

  group('UnleashDataProviderFeatureGetters', () {
    test('covers every extension getter', () {
      expect(getterCases, hasLength(33));
    });

    test('each getter reads its unleash toggle when enabled', () async {
      final allOn = {
        for (final (_, toggleName) in getterCases) toggleName: true,
        'MeetAudioDenoise': true,
      };

      final provider = createUnleashTestProvider(
        appCoreManager,
        mockAppCore,
        toggles: allOn,
      );
      await provider.start();

      for (final (getter, toggleName) in getterCases) {
        expect(getter(provider), isTrue, reason: toggleName);
      }

      await provider.clear();
    });

    test('each getter returns false when its toggle is off', () async {
      final provider = createUnleashTestProvider(appCoreManager, mockAppCore);
      await provider.start();

      for (final (getter, toggleName) in getterCases) {
        expect(getter(provider), isFalse, reason: toggleName);
      }

      await provider.clear();
    });

    test('denoise child getters respect parent flag', () async {
      final provider = createUnleashTestProvider(
        appCoreManager,
        mockAppCore,
        toggles: const {
          'MeetAudioDenoise': false,
          'MeetAudioDenoiseRnnoise': true,
          'MeetAudioDenoiseDeepfilter': true,
          'MeetAudioDenoiseDtlnRs': true,
        },
      );
      await provider.start();

      expect(provider.isMeetAudioDenoiseRnnoise(), isFalse);
      expect(provider.isMeetAudioDenoiseDeepfilter(), isFalse);
      expect(provider.isMeetAudioDenoiseDtlnRs(), isFalse);

      await provider.clear();
    });
  });
}
