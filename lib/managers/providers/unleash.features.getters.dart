import 'package:meet/managers/providers/unleash.data.provider.dart';

/// Named accessors for feature flags.
extension UnleashDataProviderFeatureGetters on UnleashDataProvider {
  bool isMeetSeamlessKeyRotationEnabled() =>
      isFeatureEnabled(UnleashFeature.meetSeamlessKeyRotationEnabled);

  bool isMeetUseCachedServerTime() =>
      isFeatureEnabled(UnleashFeature.meetUseCachedServerTime);

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

  bool isMeetInAppStoreReviewEnabled() =>
      isFeatureEnabled(UnleashFeature.meetInAppStoreReview);

  bool isMeetMultipleRecording() =>
      isFeatureEnabled(UnleashFeature.meetMultipleRecording);

  /// Native local recording controls (host/admin start/stop in room UI).
  bool isMeetMeetingRecordingNative() =>
      isFeatureEnabled(UnleashFeature.meetMeetingRecordingNative);

  /// Native subscription / upgrade (StoreKit / Play Billing) via method channel.
  bool isMeetInAppPurchaseEnabled() =>
      isFeatureEnabled(UnleashFeature.meetInAppPurchase);

  /// Native pipeline for camera background blur (pass-through until ML / Vision ship).
  bool isMeetCameraBackgroundBlur() =>
      isFeatureEnabled(UnleashFeature.meetCameraBackgroundBlur);

  /// Experimental: in app update (currently only support android)
  bool isMeetMobileInAppUpdate() =>
      isFeatureEnabled(UnleashFeature.meetMobileInAppUpdate);

  /// Warning banner for outdated mobile clients when joining a meeting.
  bool isMeetMobileUpgradeWarning() =>
      isFeatureEnabled(UnleashFeature.meetMobileUpgradeWarning);

  /// Warning banner for Android devices below the supported minimum SDK.
  bool isOldAndroidSdkWarning() =>
      isFeatureEnabled(UnleashFeature.oldAndroidSdkWarning);

  /// Warning banner for iOS versions below the supported minimum.
  bool isOldIosSdkWarning() =>
      isFeatureEnabled(UnleashFeature.oldIosSdkWarning);

  /// Parent flag for native mic denoise (RNNoise / DTLN / DeepFilter).
  bool isMeetAudioDenoise() =>
      isFeatureEnabled(UnleashFeature.meetAudioDenoise);

  bool isMeetAudioDenoiseRnnoise() =>
      isFeatureEnabled(UnleashFeature.meetAudioDenoiseRnnoise);

  bool isMeetAudioDenoiseDeepfilter() =>
      isFeatureEnabled(UnleashFeature.meetAudioDenoiseDeepfilter);

  bool isMeetAudioDenoiseDtlnRs() =>
      isFeatureEnabled(UnleashFeature.meetAudioDenoiseDtlnRs);

  /// Controls whether waiting-room switch UI is shown. Does not affect the
  /// server-driven waiting-room join flow.
  bool isMeetWaitingRoom() => isFeatureEnabled(UnleashFeature.meetWaitingRoom);

  /// MimiV1 chat: threads + event-based emoji reactions.
  bool isMeetNewChatHandling() =>
      isFeatureEnabled(UnleashFeature.meetNewChatHandling);

  /// Long-press chat message actions (quick reactions + thread reply sheet).
  bool isMeetChatThreads() => isFeatureEnabled(UnleashFeature.meetChatThreads);

  /// @mentions in chat composer and notifications.
  bool isMeetChatMentions() =>
      isFeatureEnabled(UnleashFeature.meetChatMentions);

  /// Settings rows that are designed but not wired to logic yet. They render
  /// disabled, so this is a preview / QA gate rather than a product feature.
  bool isMeetSettingsPreview() =>
      isFeatureEnabled(UnleashFeature.meetSettingsPreview);

  /// Main switch for live captions (Settings option and related UI).
  bool isMeetLiveCaptions() =>
      isFeatureEnabled(UnleashFeature.meetLiveCaptions);

  /// Spoken-language picker UI in meeting settings and captions sheet.
  bool isMeetLiveCaptionsLanguageSelector() =>
      isFeatureEnabled(UnleashFeature.meetLiveCaptionsLanguageSelector);
  bool isMeetNewJoinFunctions() =>
      isFeatureEnabled(UnleashFeature.meetNewJoinFunctions);
}
