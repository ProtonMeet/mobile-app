import 'package:flutter_test/flutter_test.dart';
import 'package:meet/constants/app.config.dart';
import 'package:meet/constants/env.dart';

import '../helper.dart';

void main() {
  testUnit('AppConfig instance creation', () {
    final appConfig = AppConfig(apiEnv: const ApiEnv.prod(), testMode: false);

    expect(appConfig.apiEnv, const ApiEnv.prod());
    expect(appConfig.testMode, false);
  });

  testUnit('Predefined configuration for production', () {
    expect(appConfigForProduction.apiEnv, const ApiEnv.prod());
    expect(appConfigForProduction.testMode, false);
  });

  testUnit('Predefined configuration for test environments', () {
    expect(appConfigForTestNet.apiEnv, ApiEnv.atlas(null));
    expect(appConfigForTestNet.testMode, true);

    expect(appConfigForRegtest.apiEnv, ApiEnv.atlas(null));
    expect(appConfigForRegtest.testMode, true);

    expect(appConfigForPayments.apiEnv, payments);
    expect(appConfigForPayments.testMode, true);
  });

  testUnit('AppConfig copyWith method', () {
    final updatedConfig = appConfigForTestNet.copyWith(
      apiEnv: const ApiEnv.prod(),
    );

    expect(updatedConfig.apiEnv, const ApiEnv.prod()); // Updated
    expect(updatedConfig.testMode, true); // Unchanged
  });

  testUnit('AppConfig.initAppEnv for "payment" environment', () {
    AppConfig.initAppEnv(customEnv: 'payment');
    expect(appConfig, equals(appConfigForPayments));
  });

  testUnit('AppConfig.initAppEnv for "prod" environment', () {
    AppConfig.initAppEnv(customEnv: 'prod');
    expect(appConfig, equals(appConfigForProduction));
  });

  testUnit('AppConfig.initAppEnv for "atlas" environment', () {
    AppConfig.initAppEnv(customEnv: 'atlas');
    expect(appConfig.apiEnv, equals(ApiEnv.atlas(null)));
  });

  testUnit('AppConfig.initAppEnv for custom value', () {
    const customEnv = 'custom';
    AppConfig.initAppEnv(customEnv: customEnv);
    expect(appConfig.apiEnv, equals(ApiEnv.atlas(customEnv)));
  });

  testUnit('should default to "prod" environment', () {
    AppConfig.initAppEnv(); // No environment parameter
    expect(appConfig, equals(appConfigForProduction));
  });

  testUnit('AppConfig.initAppEnv for "staging" environment', () {
    AppConfig.initAppEnv(customEnv: 'staging');
    expect(appConfig, equals(appConfigForStaging));
    expect(appConfig.apiEnv, const ApiEnv.staging());
  });

  testUnit('AppConfig.initAppEnv for empty string defaults to production', () {
    AppConfig.initAppEnv(customEnv: '');
    expect(appConfig, equals(appConfigForProduction));
  });

  testUnit('AppConfig should preserve testMode in copyWith', () {
    final testConfig = AppConfig(
      apiEnv: const ApiEnv.prod(),
      testMode: true,
      testMockStorage: '/test/path',
    );
    final updatedConfig = testConfig.copyWith(apiEnv: const ApiEnv.staging());
    expect(updatedConfig.testMode, isTrue);
    expect(updatedConfig.testMockStorage, equals('/test/path'));
    expect(updatedConfig.apiEnv, const ApiEnv.staging());
  });

  testUnit('AppConfig should preserve testMockStorage in copyWith', () {
    final testConfig = AppConfig(
      apiEnv: const ApiEnv.prod(),
      testMode: false,
      testMockStorage: '/custom/storage',
    );
    final updatedConfig = testConfig.copyWith(apiEnv: const ApiEnv.local());
    expect(updatedConfig.testMockStorage, equals('/custom/storage'));
    expect(updatedConfig.testMode, isFalse);
  });

  testUnit('Predefined appConfigForMLSTest should have correct values', () {
    expect(appConfigForMLSTest.apiEnv, equals(ApiEnv.atlas("sherrington")));
    expect(appConfigForMLSTest.testMode, isFalse);
  });

  testUnit('Predefined appConfigForStaging should have correct values', () {
    expect(appConfigForStaging.apiEnv, const ApiEnv.staging());
    expect(appConfigForStaging.testMode, isFalse);
  });

  testUnit(
    'initAppEnv should skip when testMode is set with testMockStorage',
    () {
      // Set up test mode with mock storage
      final originalConfig = appConfig;
      appConfig = AppConfig(
        apiEnv: const ApiEnv.prod(),
        testMode: true,
        testMockStorage: '/test/storage',
      );

      // Try to initialize - should be skipped
      AppConfig.initAppEnv(customEnv: 'staging');

      // Config should remain unchanged
      expect(appConfig.testMode, isTrue);
      expect(appConfig.testMockStorage, equals('/test/storage'));

      // Restore original config
      appConfig = originalConfig;
    },
  );
}
