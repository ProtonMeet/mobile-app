class PreferenceKeys {
  static const String eventLoopErrorCount =
      "proton_meet_app_k_event_loop_error_count";
  static const String latestEventId = "proton_meet_app_k_latest_event_id";

  static const String appDatabaseForceVersion =
      "proton_meet_app_k_app_database_force_version";
  static const String appRustDatabaseForceVersion =
      "proton_meet_app_k_app_rust_database_force_version";

  static const String inAppReviewTimmer =
      "proton_meet_app_k_in_app_review_timmer_key";

  /// Last time the OS store review dialog was requested (epoch seconds).
  /// Persists per install so we do not prompt more than once / 30 days.
  static const String inAppReviewLastRequestedEpoch =
      "proton_meet_app_k_in_app_review_last_epoch";

  /// JSON blob: meeting creates/completes, feedback history, deferred review flag.
  static const String userActivityStateV1 =
      "proton_meet_app_k_user_activity_state_v1";

  /// Last ApiEnv.cacheIsolationKey used for cold start; drives env-change wipe.
  static const String lastApiEnvCacheKey =
      "proton_meet_app_k_last_api_env_cache_isolation";

  static const String speakerPhoneEnabled =
      "proton_meet_app_k_speaker_phone_enabled";
}

/// Keys that persist across logout and should only reset on reinstall
/// (or when explicitly cleared in migrations).
Set<String> appPerInstallPreferenceKeys = {
  PreferenceKeys.lastApiEnvCacheKey,
  PreferenceKeys.inAppReviewLastRequestedEpoch,
  PreferenceKeys.userActivityStateV1,
};
