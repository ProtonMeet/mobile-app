import 'package:meet/helper/extension/datetime.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/managers/manager.dart';
import 'package:meet/managers/preferences/preferences.keys.dart';
import 'package:meet/managers/preferences/preferences.manager.dart';
import 'package:meet/models/user_activity.model.dart';

/// Tracks meeting creation, completion, and meeting feedback for deferred in-app review.
class UserActivityManager implements Manager {
  UserActivityManager(this._prefs);

  final PreferencesManager _prefs;

  Future<UserActivityPersistedV1> _read() async {
    final raw = await _prefs.storage.read(PreferenceKeys.userActivityStateV1);
    return UserActivityPersistedV1.fromPreferenceJsonString(
      raw,
      onParseFailure: (e, st) {
        l.logger.w('[UserActivity] parse state failed: $e', stackTrace: st);
      },
    );
  }

  Future<void> _write(UserActivityPersistedV1 s) async {
    await _prefs.storage.write(
      PreferenceKeys.userActivityStateV1,
      s.toPreferenceJsonString(),
    );
  }

  Future<int> _globalLastReviewEpoch() async {
    final raw = await _prefs.storage.read(
      PreferenceKeys.inAppReviewLastRequestedEpoch,
    );
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw) ?? 0;
    return 0;
  }

  Future<void> _setGlobalLastReviewEpoch(int epochSec) async {
    await _prefs.storage.write(
      PreferenceKeys.inAppReviewLastRequestedEpoch,
      epochSec,
    );
  }

  Future<int> _effectiveLastStoreReviewEpoch() async {
    final g = await _globalLastReviewEpoch();
    final legacyRaw = await _prefs.storage.read(
      PreferenceKeys.inAppReviewTimmer,
    );
    final legacy = legacyRaw is int ? legacyRaw : 0;
    return g > legacy ? g : legacy;
  }

  ///########################################################
  /// Whether the global store-review cooldown is active.
  Future<bool> isGlobalStoreReviewCooldownActive() async {
    final now = DateTime.now().secondsSinceEpoch();
    final last = await _effectiveLastStoreReviewEpoch();
    return now - last < thirtyDaysInSeconds;
  }

  Future<void> recordMeetingCreatedSuccessfully() async {
    final s = await _read();
    await _write(s.withMeetingCreated(DateTime.now().secondsSinceEpoch()));
  }

  /// Call after a normal meeting end (user left / host ended), not when kicked.
  ///
  /// [hadBadConnection]: set when LiveKit saw reconnect attempts during the call.
  /// [wasInterrupted]: set when the session used the app-level rejoin flow at least once.
  Future<void> recordMeetingCompletedAndRequestDeferredReview({
    bool hadBadConnection = false,
    bool wasInterrupted = false,
  }) async {
    final s = await _read();
    await _write(
      s.withMeetingCompleted(
        DateTime.now().secondsSinceEpoch(),
        hadBadConnection: hadBadConnection,
        wasInterrupted: wasInterrupted,
      ),
    );
  }

  /// Call after meeting feedback is successfully sent to the API.
  Future<void> recordFeedbackSubmitted({required int score}) async {
    final s = await _read();
    await _write(
      s.withFeedback(
        epochSec: DateTime.now().secondsSinceEpoch(),
        score: score,
      ),
    );
  }

  /// Whether persisted engagement + pending flag + cooldown allow attempting
  /// the OS store-review prompt on this launch.
  Future<bool> isDeferredStoreReviewReadyForPrompt() async {
    final state = await _read();
    if (!state.pendingDeferredStoreReview) return false;
    if (!state.meetsStoreReviewEngagementRules()) return false;
    if (await isGlobalStoreReviewCooldownActive()) return false;
    if (state.isPreRatingNegativeCooldownActive()) return false;
    return true;
  }

  /// User chose the negative option on the pre-rating sheet: clear deferred
  /// review and start [kPreRatingNegativeCooldownSeconds] so the sheet is not
  /// offered again immediately.
  Future<void> recordPreRatingNegativeResponse() async {
    final s = await _read();
    final now = DateTime.now().secondsSinceEpoch();
    await _write(
      s.copyWith(
        pendingDeferredStoreReview: false,
        lastPreRatingNegativeEpochSec: now,
      ),
    );
  }

  /// Clears the "show on next launch" flag after a successful prompt (or when abandoning).
  Future<void> clearDeferredStoreReviewPending() async {
    final s = await _read();
    await _write(s.copyWith(pendingDeferredStoreReview: false));
  }

  /// Persists global 30-day store-review cooldown (and legacy iOS/mac key).
  Future<void> markGlobalInAppReviewPromptCompleted() async {
    final now = DateTime.now().secondsSinceEpoch();
    await _setGlobalLastReviewEpoch(now);
    if (iOS || macOS) {
      await _prefs.storage.write(PreferenceKeys.inAppReviewTimmer, now);
    }
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<void> init() async {}

  @override
  Future<void> login(String userID) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<void> reload() async {}

  @override
  Priority getPriority() => Priority.level5;
}
