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
  static const String inAppReviewDetailCounter =
      "proton_meet_app_k_in_app_review_details_counter_key";

  /// Last ApiEnv.cacheIsolationKey used for cold start; drives env-change wipe.
  static const String lastApiEnvCacheKey =
      "proton_meet_app_k_last_api_env_cache_isolation";
}

/// Keys that persist across logout and should only reset on reinstall
/// (or when explicitly cleared in migrations).
Set<String> appPerInstallPreferenceKeys = {
  PreferenceKeys.lastApiEnvCacheKey,
};
