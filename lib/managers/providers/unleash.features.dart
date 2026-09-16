import 'package:unleash_proxy_client_flutter/toggle_config.dart';
import 'package:unleash_proxy_client_flutter/variant.dart';

/// Const-friendly client bootstrap default. Converted to [ToggleConfig] for Unleash.
///
/// Pass on [UnleashFeature] when the server may omit the toggle:
/// ```dart
/// meetVp9('MeetVp9', clientDefault: FeatureClientDefault.off),
/// meetFoo('MeetFoo', clientDefault: FeatureClientDefault.on),
/// meetBar('MeetBar', clientDefault: FeatureClientDefault(enabled: true, variantName: 'beta')),
/// ```
class FeatureClientDefault {
  const FeatureClientDefault({
    this.enabled = false,
    this.impressionData = false,
    this.variantName = 'disabled',
    this.variantEnabled = false,
  });

  static const off = FeatureClientDefault();
  static const on = FeatureClientDefault(
    enabled: true,
    variantEnabled: true,
    variantName: 'enabled',
  );

  final bool enabled;
  final bool impressionData;
  final String variantName;
  final bool variantEnabled;

  ToggleConfig toToggleConfig() => ToggleConfig(
    enabled: enabled,
    impressionData: impressionData,
    variant: Variant(enabled: variantEnabled, name: variantName),
  );
}

/// Feature flags. [toggleName] is the Unleash toggle id; [parent] gates child
/// flags (e.g. denoise backends require [meetAudioDenoise]).
enum UnleashFeature {
  meetSeamlessKeyRotationEnabled('MeetSeamlessKeyRotationEnabled'),
  meetNewJoinType('MeetNewJoinType'),
  meetScreenShare('MeetScreenShare'),
  meetPictureInPicture('MeetPictureInPicture'),
  meetClientMetricsLog('MeetClientMetricsLog'),
  meetMobileSpeakerToggle('MeetMobileSpeakerToggle'),
  meetVp9('MeetVp9', clientDefault: FeatureClientDefault.off),
  meetH264('MeetH264', clientDefault: FeatureClientDefault.off),
  meetSwitchJoinType('MeetSwitchJoinType'),
  meetNewSwitchJoinType('MeetNewSwitchJoinType'),
  isNeedForceUpgrade(
    'NeedForceUpgrade',
    clientDefault: FeatureClientDefault.off,
  ),
  meetScheduleInAdvance('MeetScheduleInAdvance'),
  meetAutoReconnection('MeetAutoReconnection'),
  meetMobileEnableNetworkTool('MeetMobileEnableNetworkTool'),
  meetAdminLowerHand(
    'MeetAdminLowerHand',
    clientDefault: FeatureClientDefault.off,
  ),
  meetShowProtonCalendar(
    'MeetShowProtonCalendar',
    clientDefault: FeatureClientDefault.off,
  ),
  meetFeedbackOnSkip('MeetFeedbackOnSkip'),
  meetInAppStoreReview('MeetInAppStoreReview'),
  meetMultipleRecording('MeetMultipleRecording'),

  /// Native local meeting recording (ReplayKit / ScreenCaptureKit controls).
  meetMeetingRecordingNative('MeetingRecordingNative'),
  meetInAppPurchase('MeetInAppPurchase'),

  /// Experimental: in app update (currently only support android)
  meetMobileInAppUpdate(
    'MeetMobileInAppUpdate',
    clientDefault: FeatureClientDefault.off,
  ),

  /// When enabled, show a warning banner on join for outdated mobile clients.
  meetMobileUpgradeWarning('MeetMobileUpgradeWarning'),

  // Native camera background blur (iOS / Android / macOS).
  meetCameraBackgroundBlur('MeetCameraBackgroundBlur'),

  /// Experimental: native microphone denoise (parent flag).
  meetAudioDenoise('MeetAudioDenoise'),

  /// RNNoise backend under [meetAudioDenoise].
  meetAudioDenoiseRnnoise('MeetAudioDenoiseRnnoise', parent: meetAudioDenoise),

  /// DeepFilter backend under [meetAudioDenoise] (stub until model ships).
  meetAudioDenoiseDeepfilter(
    'MeetAudioDenoiseDeepfilter',
    parent: meetAudioDenoise,
  ),

  /// dtln-rs (DTLN) backend under [meetAudioDenoise].
  meetAudioDenoiseDtlnRs('MeetAudioDenoiseDtlnRs', parent: meetAudioDenoise),

  /// Controls visibility of waiting-room switch UI (schedule / create / prejoin / in-room).
  /// The join flow is still driven by the server meeting info, independent of this flag.
  meetWaitingRoom('MeetWaitingRoom'),

  /// MimiV1 chat handling: threads + event-based emoji reactions.
  /// When disabled, chat falls back to the legacy encrypt/decrypt path
  /// (no threads, no MimiV1 reactions).
  meetNewChatHandling('MeetNewChatHandling'),

  /// Long-press message actions: quick reactions + thread reply bottom sheet.
  meetChatThreads('MeetChatThreads'),

  /// When enabled, MLS operations use cached server time from HTTP response headers.
  /// When disabled, they fall back to the local clock.
  meetUseCachedServerTime(
    'MeetUseCachedServerTime',
    clientDefault: FeatureClientDefault.off,
  ),

  /// Main switch for live captions (Settings UI and related flows).
  meetLiveCaptions('MeetLiveCaptions'),

  /// Spoken-language picker in meeting settings and captions sheet header.
  /// Gated by [meetLiveCaptions].
  meetLiveCaptionsLanguageSelector(
    'MeetLiveCaptionsLanguageSelector',
    parent: meetLiveCaptions,
  ),

  /// Shows settings rows that are designed but not wired to logic yet
  /// (appearance, live captions, transcription, device tests, meeting timer,
  /// picture-in-picture while sharing). They render disabled. Off by default;
  /// each feature gets its own gate once it ships.
  meetSettingsPreview(
    'MeetSettingsPreview',
    clientDefault: FeatureClientDefault.off,
  ),

  meetNewJoinFunctions(
    'MeetNewJoinFunctions',
    clientDefault: FeatureClientDefault.off,
  );

  const UnleashFeature(this.toggleName, {this.clientDefault, this.parent});

  /// Unleash toggle name (may differ from the Dart enum identifier).
  final String toggleName;

  /// Bootstrap / fetch-merge default when the server omits this toggle.
  /// `null` = no client default.
  final FeatureClientDefault? clientDefault;

  /// Parent toggle that must also be enabled (denoise backends).
  final UnleashFeature? parent;

  ToggleConfig? get defaultValue => clientDefault?.toToggleConfig();
}

/// Shared client-side default for flags that must start disabled.
final ToggleConfig kClientDisabledToggle = FeatureClientDefault.off
    .toToggleConfig();

/// Local overrides for dev / QA. When a feature is present here, Unleash is
/// ignored for that flag. Only applied in debug builds.
///
/// Example — preview unreleased settings UI without Unleash:
/// ```dart
/// const Map<UnleashFeature, bool> kUnleashLocalOverrides = {
///   UnleashFeature.meetSettingsPreview: true,
/// };
/// ```
const Map<UnleashFeature, bool> kUnleashLocalOverrides = {
  // UnleashFeature.meetSettingsPreview: true,
  // UnleashFeature.meetInAppPurchase: true,
  // UnleashFeature.meetMeetingRecordingNative: true,
  // UnleashFeature.meetWaitingRoom: true,
  // UnleashFeature.meetCameraBackgroundBlur: true,
};
