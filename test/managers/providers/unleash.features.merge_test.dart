import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meet/managers/providers/unleash.features.dart';
import 'package:meet/managers/providers/unleash.features.merge.dart';

import '../../support/unleash_helpers.dart';

void main() {
  group('getDefaultToggles', () {
    test('includes only features with explicit client defaults', () {
      final defaults = getDefaultToggles();

      expect(
        defaults.keys,
        containsAll(const [
          'MeetVp9',
          'MeetH264',
          'NeedForceUpgrade',
          'MeetShowProtonCalendar',
          'MeetAdminLowerHand',
          'MeetMobileInAppUpdate',
          'MeetUseCachedServerTime',
          'MeetSettingsPreview',
        ]),
      );
      expect(defaults.keys, isNot(contains('MeetWaitingRoom')));

      expect(defaults['MeetVp9']!.enabled, isFalse);
      expect(defaults['MeetMobileInAppUpdate']!.enabled, isFalse);
      expect(defaults['MeetSettingsPreview']!.enabled, isFalse);
    });

    test('matches count of enum entries with clientDefault', () {
      final withDefault = UnleashFeature.values
          .where((feature) => feature.clientDefault != null)
          .length;

      expect(getDefaultToggles().length, withDefault);
    });
  });

  group('mergeTogglesWithClientDefaults', () {
    test('injects all client defaults into an empty server payload', () {
      final merged =
          jsonDecode(
                mergeTogglesWithClientDefaults(
                  utf8.encode(
                    jsonEncode({'toggles': <Map<String, dynamic>>[]}),
                  ),
                ),
              )
              as Map<String, dynamic>;

      final toggles = (merged['toggles'] as List).cast<Map<String, dynamic>>();
      final byName = {for (final t in toggles) t['name'] as String: t};

      expect(byName.keys, containsAll(getDefaultToggles().keys));
      expect(byName['MeetVp9']!['enabled'], isFalse);
    });

    test('keeps client-disabled defaults for toggles omitted by server', () {
      final merged =
          jsonDecode(
                mergeTogglesWithClientDefaults(
                  encodeUnleashToggles({'MeetWaitingRoom': true}),
                ),
              )
              as Map<String, dynamic>;

      final toggles = (merged['toggles'] as List).cast<Map<String, dynamic>>();
      final byName = {for (final t in toggles) t['name'] as String: t};

      expect(byName['MeetWaitingRoom']!['enabled'], isTrue);
      expect(byName['MeetVp9']!['enabled'], isFalse);
    });

    test('lets server override a client default when present', () {
      final merged =
          jsonDecode(
                mergeTogglesWithClientDefaults(
                  encodeUnleashToggles({'MeetVp9': true}),
                ),
              )
              as Map<String, dynamic>;

      final toggles = (merged['toggles'] as List).cast<Map<String, dynamic>>();
      final meetVp9 = toggles.firstWhere((t) => t['name'] == 'MeetVp9');

      expect(meetVp9['enabled'], isTrue);
    });

    test('returns original body for invalid JSON', () {
      const invalid = 'not-json';
      expect(mergeTogglesWithClientDefaults(utf8.encode(invalid)), invalid);
    });

    test('returns original body when root is not a map', () {
      const payload = '["toggles"]';
      expect(mergeTogglesWithClientDefaults(utf8.encode(payload)), payload);
    });

    test('returns original body when toggles key is missing', () {
      const payload = '{"features":[]}';
      expect(mergeTogglesWithClientDefaults(utf8.encode(payload)), payload);
    });

    test('returns original body when toggles is not a list', () {
      const payload = '{"toggles":"invalid"}';
      expect(mergeTogglesWithClientDefaults(utf8.encode(payload)), payload);
    });

    test('skips malformed toggle entries without a string name', () {
      final body = utf8.encode(
        jsonEncode({
          'toggles': [
            {'enabled': true},
            {'name': 42, 'enabled': true},
            {'name': 'MeetWaitingRoom', 'enabled': true},
          ],
        }),
      );

      final merged =
          jsonDecode(mergeTogglesWithClientDefaults(body))
              as Map<String, dynamic>;
      final toggles = (merged['toggles'] as List).cast<Map<String, dynamic>>();
      final byName = {for (final t in toggles) t['name'] as String: t};

      expect(byName['MeetWaitingRoom']!['enabled'], isTrue);
      expect(byName.containsKey('42'), isFalse);
    });
  });
}
