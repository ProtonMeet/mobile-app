import 'package:meet/managers/preferences/preferences.interface.dart';

class LimitedDisplayPreferences {
  final PreferencesInterface storage;
  LimitedDisplayPreferences(this.storage) {
    storage.addPerInstallKey(dashboardSignInCardDismissedAt);
  }

  /// Dashboard sign-in card dismiss timestamp (epoch ms).
  final String dashboardSignInCardDismissedAt =
      "proton_meet_app_k_dashboard_sign_in_card_dismissed_at";

  ///
  Future<bool> shouldShow({required Duration defaultResetDuration}) async {
    // dismissedAtKey: PreferenceKeys.dashboardSignInCardDismissedAt,
    final dismissedRaw = await storage.read(dashboardSignInCardDismissedAt);
    final dismissedAt = _parseDateTime(dismissedRaw);
    final resetDuration = defaultResetDuration;
    final current = DateTime.now();
    if (dismissedAt == null) return true;
    return current.difference(dismissedAt) >= resetDuration;
  }

  ///
  Future<void> markDismissed(String dismissedAtKey) async {
    await storage.write(dismissedAtKey, DateTime.now().millisecondsSinceEpoch);
  }

  ///
  DateTime? _parseDateTime(dynamic value) {
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
