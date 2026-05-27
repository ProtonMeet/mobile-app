import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_review/in_app_review.dart' show InAppReview;
import 'package:meet/constants/env.dart';
import 'package:meet/helper/extension/response_error.extension.dart';
import 'package:meet/helper/logger.dart';
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/managers/services/force_upgrade.dart';
import 'package:meet/rust/errors.dart';
import 'package:unleash_proxy_client_flutter/toggle_config.dart';
import 'package:unleash_proxy_client_flutter/unleash_proxy_client_flutter.dart';
import 'package:unleash_proxy_client_flutter/variant.dart';

/// Enum for feature flags
enum UnleashFeature {
  meetSeamlessKeyRotationEnabled,
  meetNewJoinType,
  meetScreenShare,
  meetPictureInPicture,
  meetClientMetricsLog,
  meetMobileSpeakerToggle,
  meetVp9,
  meetH264,
  meetSwitchJoinType,
  meetNewSwitchJoinType,
  isNeedForceUpgrade,
  meetScheduleInAdvance,
  meetAutoReconnection,
  meetMobileEnableNetworkTool,
  meetAdminLowerHand,
  meetShowProtonCalendar,
  meetFeedbackOnSkip,
  meetInAppStoreReview,
  meetMultipleRecording,
  meetInAppPurchase,
  /// Experimental: in app update (currently only support android)
  meetMobileInAppUpdate,

  /// Experimental: native camera background blur (iOS / Android).
  meetCameraBackgroundBlur,
}

/// Function to retrieve all default toggles
Map<String, ToggleConfig> getDefaultToggles() {
  return {
    for (var feature in UnleashFeature.values)
      feature.name: ?feature.defaultValue,
  };
}

/// Extension to get feature names
extension UnleashFeatureExt on UnleashFeature {
  String get name {
    switch (this) {
      case UnleashFeature.meetSeamlessKeyRotationEnabled:
        return "MeetSeamlessKeyRotationEnabled";
      case UnleashFeature.meetNewJoinType:
        return "MeetNewJoinType";
      case UnleashFeature.meetScreenShare:
        return "MeetScreenShare";
      case UnleashFeature.meetPictureInPicture:
        return "MeetPictureInPicture";
      case UnleashFeature.meetClientMetricsLog:
        return "MeetClientMetricsLog";
      case UnleashFeature.meetMobileSpeakerToggle:
        return "MeetMobileSpeakerToggle";
      case UnleashFeature.meetVp9:
        return "MeetVp9";
      case UnleashFeature.meetH264:
        return "MeetH264";
      case UnleashFeature.meetSwitchJoinType:
        return "MeetSwitchJoinType";
      case UnleashFeature.isNeedForceUpgrade:
        return "NeedForceUpgrade";
      case UnleashFeature.meetScheduleInAdvance:
        return "MeetScheduleInAdvance";
      case UnleashFeature.meetAutoReconnection:
        return "MeetAutoReconnection";
      case UnleashFeature.meetMobileEnableNetworkTool:
        return "MeetMobileEnableNetworkTool";
      case UnleashFeature.meetAdminLowerHand:
        return "MeetAdminLowerHand";
      case UnleashFeature.meetShowProtonCalendar:
        return "MeetShowProtonCalendar";
      case UnleashFeature.meetFeedbackOnSkip:
        return "MeetFeedbackOnSkip";
      case UnleashFeature.meetInAppStoreReview:
        return "MeetInAppStoreReview";
      case UnleashFeature.meetInAppPurchase:
        return "MeetInAppPurchase";
      case UnleashFeature.meetNewSwitchJoinType:
        return "MeetNewSwitchJoinType";
      case UnleashFeature.meetMultipleRecording:
        return "MeetMultipleRecording";
      case UnleashFeature.meetMobileInAppUpdate:
        return "MeetMobileInAppUpdate";
      case UnleashFeature.meetCameraBackgroundBlur:
        return "MeetCameraBackgroundBlur";
    }
  }

  /// Returns the default toggle configuration for the feature, if applicable
  ToggleConfig? get defaultValue {
    switch (this) {
      case UnleashFeature.meetVp9:
        return ToggleConfig(
          enabled: false,
          impressionData: false,
          variant: Variant(enabled: false, name: 'disabled'),
        );
      case UnleashFeature.meetH264:
        return ToggleConfig(
          enabled: false,
          impressionData: false,
          variant: Variant(enabled: false, name: 'disabled'),
        );
      case UnleashFeature.isNeedForceUpgrade:
        return ToggleConfig(
          enabled: false,
          impressionData: false,
          variant: Variant(enabled: false, name: 'disabled'),
        );
      case UnleashFeature.meetShowProtonCalendar:
        return ToggleConfig(
          enabled: false,
          impressionData: false,
          variant: Variant(enabled: false, name: 'disabled'),
        );
      case UnleashFeature.meetAdminLowerHand:
        return ToggleConfig(
          enabled: false,
          impressionData: false,
          variant: Variant(enabled: false, name: 'disabled'),
        );
      case UnleashFeature.meetMobileInAppUpdate:
        return ToggleConfig(
          enabled: false,
          impressionData: false,
          variant: Variant(enabled: false, name: 'disabled'),
        );
      default:
        return null;
    }
  }
}

class UnleashDataProvider extends DataProvider {
  /// Unleash client for feature toggles
  late final UnleashClient unleashClient;

  final AppCoreManager appCoreManager;

  // /// API client for feature flags
  // final FrbUnleashClient frbUnleashClient;

  /// API environment configuration
  final ApiEnv apiEnv;

  /// refresh interval
  final duration = const Duration(minutes: 2).inSeconds;

  /// Timer for periodic refresh
  Timer? refreshTimer;

  UnleashDataProvider(
    this.apiEnv,
    this.appCoreManager, {
    bool bootstrapOverride = false,
  }) {
    final hostApiPath = apiEnv.apiPath;
    const appName = 'ProtonMeet';
    unleashClient = UnleashClient(
      url: Uri.parse('$hostApiPath/feature/v2/frontend'),
      clientKey: '-',
      appName: appName,
      refreshInterval: duration,
      disableMetrics: true,
      disableRefresh: true,
      bootstrapOverride: bootstrapOverride,
      bootstrap: getDefaultToggles(),
      fetcher: (http.Request request) async {
        final response = await appCoreManager.appCore.fetchToggles();
        if (kDebugMode && response.statusCode == 200) {
          try {
            final decoded = jsonDecode(utf8.decode(response.body));
            _logUnleashJson(decoded);
          } catch (e) {
            logger.w('[Unleash] Failed to decode fetchToggles response: $e');
          }
        }
        return http.Response.bytes(response.body.toList(), response.statusCode);
      },
    );
    setupUnleashListeners();
  }

  /// Sets up Unleash event listeners
  void setupUnleashListeners() {
    unleashClient.on('ready', (value) {
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
        Duration(seconds: duration),
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

  /// Generic method to check if a feature flag is enabled
  bool isFeatureEnabled(UnleashFeature feature) {
    return unleashClient.isEnabled(feature.name);
  }

  /// Check specific feature flags
  bool isMeetSeamlessKeyRotationEnabled() =>
      isFeatureEnabled(UnleashFeature.meetSeamlessKeyRotationEnabled);

  bool isMeetNewJoinType() => isFeatureEnabled(UnleashFeature.meetNewJoinType);

  bool isMeetScreenShare() => isFeatureEnabled(UnleashFeature.meetScreenShare);

  bool isMeetPictureInPicture() =>
      isFeatureEnabled(UnleashFeature.meetPictureInPicture);

  bool isMeetClientMetricsLog() =>
      isFeatureEnabled(UnleashFeature.meetClientMetricsLog);

  bool isMeetMobileSpeakerToggle() =>
      isFeatureEnabled(UnleashFeature.meetMobileSpeakerToggle);

  bool isMeetVp9() => isFeatureEnabled(UnleashFeature.meetVp9);

  bool isMeetH264() => isFeatureEnabled(UnleashFeature.meetH264);

  bool isMeetSwitchJoinType() =>
      isFeatureEnabled(UnleashFeature.meetSwitchJoinType);

  bool isMeetNewSwitchJoinType() =>
      isFeatureEnabled(UnleashFeature.meetNewSwitchJoinType);

  bool isNeedForceUpgrade() =>
      isFeatureEnabled(UnleashFeature.isNeedForceUpgrade);

  bool isMeetScheduleInAdvance() =>
      isFeatureEnabled(UnleashFeature.meetScheduleInAdvance);

  bool isMeetAutoReconnection() =>
      isFeatureEnabled(UnleashFeature.meetAutoReconnection);

  bool isMeetMobileEnableNetworkTool() =>
      isFeatureEnabled(UnleashFeature.meetMobileEnableNetworkTool);

  bool isMeetAdminLowerHand() =>
      isFeatureEnabled(UnleashFeature.meetAdminLowerHand);

  /// "Add to Proton Calendar" in join / add-to-calendar flows.
  bool isMeetShowProtonCalendar() =>
      isFeatureEnabled(UnleashFeature.meetShowProtonCalendar);

  /// When enabled, leaving the low-rating feedback flow via Skip still submits score + tags.
  bool isMeetFeedbackOnSkip() =>
      isFeatureEnabled(UnleashFeature.meetFeedbackOnSkip);

  // ignore: comment_references
  /// When false, deferred / store [InAppReview] flows are disabled (Unleash kill switch).
  bool isMeetInAppStoreReviewEnabled() =>
      isFeatureEnabled(UnleashFeature.meetInAppStoreReview);

  bool isMeetMultipleRecording() =>
      isFeatureEnabled(UnleashFeature.meetMultipleRecording);

  /// Native subscription / upgrade (StoreKit / Play Billing) via method channel.
  bool isMeetInAppPurchaseEnabled() =>
      isFeatureEnabled(UnleashFeature.meetInAppPurchase);

  /// Native pipeline for camera background blur (pass-through until ML / Vision ship).
  bool isMeetCameraBackgroundBlur() =>
      isFeatureEnabled(UnleashFeature.meetCameraBackgroundBlur);

  /// Experimental: in app update (currently only support android)
  bool isMeetMobileInAppUpdate() =>
      isFeatureEnabled(UnleashFeature.meetMobileInAppUpdate);
}
