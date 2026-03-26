import 'package:flutter_test/flutter_test.dart';
import 'package:meet/managers/preferences/preferences.manager.dart';
import 'package:mockito/mockito.dart';

import '../../helper.dart';
import '../../mocks/preferences.interface.mocks.dart';

void main() {
  testUnit(
    'LimitedDisplayPreferences shouldShow when never dismissed',
    () async {
      final mockPrefs = MockPreferencesInterface();
      when(mockPrefs.read(any)).thenAnswer((_) async => null);

      final prefs = PreferencesManager(mockPrefs);
      final limited = prefs.limitedDisplayPreferences;

      final shouldShow = await limited.shouldShow(
        defaultResetDuration: const Duration(days: 7),
      );

      expect(shouldShow, isTrue);
    },
  );

  testUnit('LimitedDisplayPreferences respects reset window', () async {
    final mockPrefs = MockPreferencesInterface();
    final storage = <String, dynamic>{};

    when(mockPrefs.write(any, any)).thenAnswer((invocation) async {
      storage[invocation.positionalArguments[0] as String] =
          invocation.positionalArguments[1];
    });
    when(mockPrefs.read(any)).thenAnswer((invocation) async {
      return storage[invocation.positionalArguments[0] as String];
    });

    final prefs = PreferencesManager(mockPrefs);
    final limited = prefs.limitedDisplayPreferences;

    await limited.markDismissed(limited.dashboardSignInCardDismissedAt);

    final shouldShow = await limited.shouldShow(
      defaultResetDuration: const Duration(days: 7),
    );

    expect(shouldShow, isFalse);
  });

  testUnit('LimitedDisplayPreferences shows after reset window', () async {
    final mockPrefs = MockPreferencesInterface();
    final prefs = PreferencesManager(mockPrefs);
    final limited = prefs.limitedDisplayPreferences;
    final oldDate = DateTime(2000).millisecondsSinceEpoch;

    when(mockPrefs.read(any)).thenAnswer((invocation) async {
      final key = invocation.positionalArguments[0] as String;
      if (key == limited.dashboardSignInCardDismissedAt) {
        return oldDate;
      }
      return null;
    });

    final shouldShow = await limited.shouldShow(
      defaultResetDuration: const Duration(days: 7),
    );

    expect(shouldShow, isTrue);
  });

  testUnit(
    'LimitedDisplayPreferences markDismissed writes timestamp',
    () async {
      final mockPrefs = MockPreferencesInterface();
      final storage = <String, dynamic>{};

      when(mockPrefs.write(any, any)).thenAnswer((invocation) async {
        storage[invocation.positionalArguments[0] as String] =
            invocation.positionalArguments[1];
      });
      when(mockPrefs.read(any)).thenAnswer((invocation) async {
        return storage[invocation.positionalArguments[0] as String];
      });

      final prefs = PreferencesManager(mockPrefs);
      final limited = prefs.limitedDisplayPreferences;

      await limited.markDismissed(limited.dashboardSignInCardDismissedAt);

      verify(
        mockPrefs.write(limited.dashboardSignInCardDismissedAt, any),
      ).called(1);

      final dismissedRaw = await mockPrefs.read(
        limited.dashboardSignInCardDismissedAt,
      );
      expect(dismissedRaw, isA<int>());
      final dismissedAt = DateTime.fromMillisecondsSinceEpoch(
        dismissedRaw as int,
      );
      final now = DateTime.now();
      expect(now.difference(dismissedAt).inSeconds, lessThan(5));
    },
  );

  testUnit(
    'LimitedDisplayPreferences handles string timestamp format',
    () async {
      final mockPrefs = MockPreferencesInterface();
      final prefs = PreferencesManager(mockPrefs);
      final limited = prefs.limitedDisplayPreferences;
      final dateStr = DateTime(2020).toIso8601String();

      when(mockPrefs.read(any)).thenAnswer((invocation) async {
        final key = invocation.positionalArguments[0] as String;
        if (key == limited.dashboardSignInCardDismissedAt) {
          return dateStr;
        }
        return null;
      });

      final shouldShow = await limited.shouldShow(
        defaultResetDuration: const Duration(days: 7),
      );

      expect(shouldShow, isTrue);
    },
  );

  testUnit(
    'LimitedDisplayPreferences handles invalid timestamp gracefully',
    () async {
      final mockPrefs = MockPreferencesInterface();
      final prefs = PreferencesManager(mockPrefs);
      final limited = prefs.limitedDisplayPreferences;

      when(mockPrefs.read(any)).thenAnswer((invocation) async {
        final key = invocation.positionalArguments[0] as String;
        if (key == limited.dashboardSignInCardDismissedAt) {
          return 'invalid_date';
        }
        return null;
      });

      final shouldShow = await limited.shouldShow(
        defaultResetDuration: const Duration(days: 7),
      );

      expect(shouldShow, isTrue);
    },
  );

  testUnit(
    'LimitedDisplayPreferences adds per-install key on construction',
    () {
      final mockPrefs = MockPreferencesInterface();
      final prefs = PreferencesManager(mockPrefs);
      final limited = prefs.limitedDisplayPreferences;

      verify(
        mockPrefs.addPerInstallKey(limited.dashboardSignInCardDismissedAt),
      ).called(1);
    },
  );
}
