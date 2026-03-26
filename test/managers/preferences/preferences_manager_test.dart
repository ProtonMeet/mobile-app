import 'package:flutter_test/flutter_test.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/managers/preferences/preferences.keys.dart';
import 'package:meet/managers/preferences/preferences.manager.dart';
import 'package:mockito/mockito.dart';

import '../../helper.dart';
import '../../mocks/preferences.interface.mocks.dart';

void main() {
  testUnit('PreferencesManager.checkif runs logic on mismatch', () async {
    final mockPrefs = MockPreferencesInterface();
    final storage = <String, dynamic>{};

    when(mockPrefs.read(any)).thenAnswer((invocation) async {
      return storage[invocation.positionalArguments[0] as String];
    });
    when(mockPrefs.write(any, any)).thenAnswer((invocation) async {
      storage[invocation.positionalArguments[0] as String] =
          invocation.positionalArguments[1];
    });
    when(
      mockPrefs.toMap(),
    ).thenAnswer((_) => Map<dynamic, dynamic>.from(storage));

    final prefs = PreferencesManager(mockPrefs);
    var called = 0;

    await prefs.checkif('flag', true, () async {
      called += 1;
    });

    expect(called, 1);
    expect(storage['flag'], isTrue);
  });

  testUnit('PreferencesManager.checkif skips when value matches', () async {
    final mockPrefs = MockPreferencesInterface();
    final storage = <String, dynamic>{'flag': true};

    when(mockPrefs.read(any)).thenAnswer((invocation) async {
      return storage[invocation.positionalArguments[0] as String];
    });
    when(mockPrefs.write(any, any)).thenAnswer((invocation) async {
      storage[invocation.positionalArguments[0] as String] =
          invocation.positionalArguments[1];
    });

    final prefs = PreferencesManager(mockPrefs);
    var called = 0;

    await prefs.checkif('flag', true, () async {
      called += 1;
    });

    expect(called, 0);
  });

  testUnit(
    'PreferencesManager.isFirstTimeEntry runs logic on first entry',
    () async {
      final mockPrefs = MockPreferencesInterface();
      final storage = <String, dynamic>{};

      when(mockPrefs.read(any)).thenAnswer((invocation) async {
        return storage[invocation.positionalArguments[0] as String];
      });
      when(mockPrefs.write(any, any)).thenAnswer((invocation) async {
        storage[invocation.positionalArguments[0] as String] =
            invocation.positionalArguments[1];
      });
      when(
        mockPrefs.toMap(),
      ).thenAnswer((_) => Map<dynamic, dynamic>.from(storage));

      final prefs = PreferencesManager(mockPrefs);
      var called = 0;

      await prefs.isFirstTimeEntry(() async {
        called += 1;
      });

      expect(called, 1);
      expect(storage[prefs.firstTimeEntryKey], isFalse);
    },
  );

  testUnit(
    'PreferencesManager.isFirstTimeEntry skips when not first entry',
    () async {
      final mockPrefs = MockPreferencesInterface();
      final prefs = PreferencesManager(mockPrefs);
      final storage = <String, dynamic>{prefs.firstTimeEntryKey: false};

      when(mockPrefs.read(any)).thenAnswer((invocation) async {
        return storage[invocation.positionalArguments[0] as String];
      });
      when(mockPrefs.write(any, any)).thenAnswer((invocation) async {
        storage[invocation.positionalArguments[0] as String] =
            invocation.positionalArguments[1];
      });

      var called = 0;

      await prefs.isFirstTimeEntry(() async {
        called += 1;
      });

      expect(called, 0);
    },
  );

  testUnit('PreferencesManager.delete removes key', () async {
    final mockPrefs = MockPreferencesInterface();
    final storage = <String, dynamic>{'test_key': 'value'};

    when(mockPrefs.write(any, any)).thenAnswer((invocation) async {
      storage[invocation.positionalArguments[0] as String] =
          invocation.positionalArguments[1];
    });
    when(mockPrefs.delete(any)).thenAnswer((invocation) async {
      storage.remove(invocation.positionalArguments[0] as String);
    });
    when(
      mockPrefs.toMap(),
    ).thenAnswer((_) => Map<dynamic, dynamic>.from(storage));

    final prefs = PreferencesManager(mockPrefs);

    await prefs.delete('test_key');

    expect(storage['test_key'], isNull);
  });

  testUnit('PreferencesManager.toMap returns storage map', () async {
    final mockPrefs = MockPreferencesInterface();
    final storage = <String, dynamic>{'key1': 'value1', 'key2': 42};

    when(
      mockPrefs.toMap(),
    ).thenAnswer((_) => Map<dynamic, dynamic>.from(storage));

    final prefs = PreferencesManager(mockPrefs);

    final map = prefs.toMap();

    expect(map['key1'], 'value1');
    expect(map['key2'], 42);
  });

  testUnit('PreferencesManager.logout clears non-per-install keys', () async {
    final mockPrefs = MockPreferencesInterface();
    final storage = <String, dynamic>{
      'per_install_key': 'keep',
      'temp_key': 'delete',
    };
    final perInstallKeys = <String>{'per_install_key'};

    when(mockPrefs.write(any, any)).thenAnswer((invocation) async {
      storage[invocation.positionalArguments[0] as String] =
          invocation.positionalArguments[1];
    });
    when(mockPrefs.delete(any)).thenAnswer((invocation) async {
      storage.remove(invocation.positionalArguments[0] as String);
    });
    when(mockPrefs.deleteAll(clearAll: anyNamed('clearAll'))).thenAnswer((
      invocation,
    ) async {
      final clearAll = invocation.namedArguments[#clearAll] as bool;
      if (clearAll) {
        storage.clear();
      } else {
        final keys = storage.keys.toList();
        for (final key in keys) {
          if (!perInstallKeys.contains(key)) {
            storage.remove(key);
          }
        }
      }
    });
    when(
      mockPrefs.toMap(),
    ).thenAnswer((_) => Map<dynamic, dynamic>.from(storage));

    final prefs = PreferencesManager(mockPrefs);
    mockPrefs.addPerInstallKey('per_install_key');

    await prefs.logout();

    expect(storage['per_install_key'], 'keep');
    expect(storage['temp_key'], isNull);
  });

  testUnit('PreferencesManager.rebuild writes database versions', () async {
    final mockPrefs = MockPreferencesInterface();
    final storage = <String, dynamic>{};

    when(mockPrefs.write(any, any)).thenAnswer((invocation) async {
      storage[invocation.positionalArguments[0] as String] =
          invocation.positionalArguments[1];
    });
    when(
      mockPrefs.toMap(),
    ).thenAnswer((_) => Map<dynamic, dynamic>.from(storage));

    final prefs = PreferencesManager(mockPrefs);

    await prefs.rebuild();

    expect(storage[prefs.firstTimeEntryKey], isFalse);
    expect(
      storage[PreferenceKeys.appDatabaseForceVersion],
      driftDatabaseVersion,
    );
    expect(
      storage[PreferenceKeys.appRustDatabaseForceVersion],
      rustDatabaseVersion,
    );
  });

  testUnit('PreferencesManager.saveDisplayName sanitizes and saves', () async {
    final mockPrefs = MockPreferencesInterface();
    final storage = <String, dynamic>{};

    when(mockPrefs.write(any, any)).thenAnswer((invocation) async {
      storage[invocation.positionalArguments[0] as String] =
          invocation.positionalArguments[1];
    });
    when(
      mockPrefs.toMap(),
    ).thenAnswer((_) => Map<dynamic, dynamic>.from(storage));

    final prefs = PreferencesManager(mockPrefs);

    await prefs.saveDisplayName(displayName: '  Test Name  ', isGuest: false);

    final saved = storage['proton.meet.displayName'] as String?;
    expect(saved, isNotNull);
    expect(saved!.trim(), 'Test Name');
  });

  testUnit('PreferencesManager.saveDisplayName ignores empty', () async {
    final mockPrefs = MockPreferencesInterface();
    final storage = <String, dynamic>{};

    when(mockPrefs.write(any, any)).thenAnswer((invocation) async {
      storage[invocation.positionalArguments[0] as String] =
          invocation.positionalArguments[1];
    });
    when(
      mockPrefs.toMap(),
    ).thenAnswer((_) => Map<dynamic, dynamic>.from(storage));

    final prefs = PreferencesManager(mockPrefs);

    await prefs.saveDisplayName(displayName: '   ', isGuest: false);

    expect(storage['proton.meet.displayName'], isNull);
  });

  testUnit('PreferencesManager.getDisplayName returns saved name', () async {
    final mockPrefs = MockPreferencesInterface();
    final storage = <String, dynamic>{'proton.meet.displayName': 'Test Name'};

    when(mockPrefs.read(any)).thenAnswer((invocation) async {
      return storage[invocation.positionalArguments[0] as String];
    });

    final prefs = PreferencesManager(mockPrefs);

    final name = await prefs.getDisplayName(isGuest: false);

    expect(name, 'Test Name');
  });

  testUnit('PreferencesManager.getDisplayName returns null on error', () async {
    final mockPrefs = MockPreferencesInterface();
    final storage = <String, dynamic>{'proton.meet.displayName': 123};

    when(mockPrefs.read(any)).thenAnswer((invocation) async {
      return storage[invocation.positionalArguments[0] as String];
    });

    final prefs = PreferencesManager(mockPrefs);

    final name = await prefs.getDisplayName(isGuest: false);

    expect(name, isNull);
  });

  testUnit('PreferencesManager.clearDisplayName deletes key', () async {
    final mockPrefs = MockPreferencesInterface();
    final storage = <String, dynamic>{'proton.meet.displayName': 'Test'};

    when(mockPrefs.delete(any)).thenAnswer((invocation) async {
      storage.remove(invocation.positionalArguments[0] as String);
    });
    when(
      mockPrefs.toMap(),
    ).thenAnswer((_) => Map<dynamic, dynamic>.from(storage));

    final prefs = PreferencesManager(mockPrefs);

    await prefs.clearDisplayName(isGuest: false);

    expect(storage['proton.meet.displayName'], isNull);
  });

  testUnit(
    'PreferencesManager.saveKeepDisplayNamePreference saves value',
    () async {
      final mockPrefs = MockPreferencesInterface();
      final storage = <String, dynamic>{};

      when(mockPrefs.write(any, any)).thenAnswer((invocation) async {
        storage[invocation.positionalArguments[0] as String] =
            invocation.positionalArguments[1];
      });
      when(
        mockPrefs.toMap(),
      ).thenAnswer((_) => Map<dynamic, dynamic>.from(storage));

      final prefs = PreferencesManager(mockPrefs);

      await prefs.saveKeepDisplayNamePreference(keep: false, isGuest: false);

      expect(storage['proton.meet.keepDisplayName'], isFalse);
    },
  );

  testUnit(
    'PreferencesManager.getKeepDisplayNamePreference defaults to true',
    () async {
      final mockPrefs = MockPreferencesInterface();
      final storage = <String, dynamic>{};

      when(mockPrefs.read(any)).thenAnswer((invocation) async {
        return storage[invocation.positionalArguments[0] as String];
      });

      final prefs = PreferencesManager(mockPrefs);

      final keep = await prefs.getKeepDisplayNamePreference(isGuest: false);

      expect(keep, isTrue);
    },
  );

  testUnit(
    'PreferencesManager.getKeepDisplayNamePreference returns saved value',
    () async {
      final mockPrefs = MockPreferencesInterface();
      final storage = <String, dynamic>{'proton.meet.keepDisplayName': false};

      when(mockPrefs.read(any)).thenAnswer((invocation) async {
        return storage[invocation.positionalArguments[0] as String];
      });

      final prefs = PreferencesManager(mockPrefs);

      final keep = await prefs.getKeepDisplayNamePreference(isGuest: false);

      expect(keep, isFalse);
    },
  );

  testUnit(
    'PreferencesManager.clearAllDisplayNameData deletes both keys',
    () async {
      final mockPrefs = MockPreferencesInterface();
      final storage = <String, dynamic>{
        'proton.meet.displayName': 'Test',
        'proton.meet.keepDisplayName': true,
      };

      when(mockPrefs.delete(any)).thenAnswer((invocation) async {
        storage.remove(invocation.positionalArguments[0] as String);
      });
      when(
        mockPrefs.toMap(),
      ).thenAnswer((_) => Map<dynamic, dynamic>.from(storage));

      final prefs = PreferencesManager(mockPrefs);

      await prefs.clearAllDisplayNameData(isGuest: false);

      expect(storage['proton.meet.displayName'], isNull);
      expect(storage['proton.meet.keepDisplayName'], isNull);
    },
  );
}
