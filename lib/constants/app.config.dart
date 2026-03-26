import 'package:meet/constants/env.dart';
import 'package:meet/helper/logger.dart';

/// Application configuration class that holds environment and test settings.
class AppConfig {
  /// API environment configuration.
  final ApiEnv apiEnv;

  /// Flag for enabling/disabling test mode.
  /// When true, enables test-specific behaviors and outputs.
  final bool testMode;

  /// Path of storage for test mode.
  /// Used when testMode is true to specify a custom storage location.
  final String? testMockStorage;

  /// Creates an AppConfig instance.
  ///
  /// [apiEnv] - The API environment to use (prod, staging, atlas, local).
  /// [testMode] - Whether to enable test mode.
  /// [testMockStorage] - Optional custom storage path for test mode.
  AppConfig({
    required this.apiEnv,
    required this.testMode,
    this.testMockStorage,
  });

  /// Initializes the application environment configuration.
  ///
  /// If [customEnv] is provided, it will be used; otherwise, it reads from
  /// the compile-time environment variable 'appEnv' (defaults to 'prod').
  ///
  /// Supported environments:
  /// - 'payment': Payment test environment
  /// - 'prod': Production environment
  /// - 'staging': Staging environment
  /// - 'atlas': Atlas environment (default atlas)
  /// - Any other non-empty string: Custom atlas environment
  ///
  /// If test mode is already set with testMockStorage, initialization is skipped.
  ///
  /// [customEnv] - Optional custom environment string. If null, reads from
  ///                compile-time environment variable.
  static void initAppEnv({String? customEnv}) {
    // if app config is already set for test mode, skip initAppEnv
    if (appConfig.testMode && appConfig.testMockStorage != null) {
      logger.i('App config already set for test mode, skipping initAppEnv');
      return;
    }

    final environment =
        customEnv ??
        const String.fromEnvironment('appEnv', defaultValue: 'prod');
    logger.i('App environment: $environment');
    switch (environment) {
      case 'payment':
        appConfig = appConfigForPayments;
      case 'prod':
        appConfig = appConfigForProduction;
      case 'staging':
        appConfig = appConfigForStaging;
      case 'atlas':
        appConfig = appConfigForRegtest.copyWith(apiEnv: ApiEnv.atlas(null));
      default:
        if (environment.isNotEmpty) {
          appConfig = appConfigForRegtest.copyWith(
            apiEnv: ApiEnv.atlas(environment),
          );
        } else {
          // Fallback to production if environment is empty
          logger.w('Empty environment provided, defaulting to production');
          appConfig = appConfigForProduction;
        }
    }
  }

  /// Creates a copy of this AppConfig with the given fields replaced.
  ///
  /// [apiEnv] - The new API environment to use.
  /// Other fields (testMode, testMockStorage) are preserved from the original.
  AppConfig copyWith({required ApiEnv apiEnv}) {
    return AppConfig(
      apiEnv: apiEnv,
      testMode: testMode,
      testMockStorage: testMockStorage,
    );
  }
}

// var appConfig = appConfigForMLSTest;
/// Global application configuration instance.
/// Defaults to production configuration.
var appConfig = appConfigForProduction;

/// Predefined app config for test net environment.
final appConfigForTestNet = AppConfig(
  apiEnv: ApiEnv.atlas(null),
  testMode: true,
);

/// Predefined app config for regtest environment.
final appConfigForRegtest = AppConfig(
  apiEnv: ApiEnv.atlas(null),
  testMode: true,
);

/// Predefined app config for payment test environment.
final appConfigForPayments = AppConfig(apiEnv: payments, testMode: true);

/// Predefined app config for production environment.
/// This is the default configuration used in production builds.
final appConfigForProduction = AppConfig(
  apiEnv: const ApiEnv.prod(),
  testMode: false,
);

/// Predefined app config for MLS test environment (sherrington).
final appConfigForMLSTest = AppConfig(
  apiEnv: ApiEnv.atlas("sherrington"),
  testMode: false,
);

/// Predefined app config for staging environment.
final appConfigForStaging = AppConfig(
  apiEnv: const ApiEnv.staging(),
  testMode: false,
);
