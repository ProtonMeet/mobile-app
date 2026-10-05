import 'package:flutter_test/flutter_test.dart';
import 'package:meet/utils/mentions/mention_composer_display.dart';
import 'package:meet/utils/mentions/mention_token.dart';

void main() {
  const localId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  const otherId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

  String resolveName(String id) => id == otherId ? 'Alice Nguyen' : id;

  group('computeMentionDisplayRanges', () {
    test('ends at @Name without swallowing trailing space', () {
      final token = getMentionToken(otherId);
      final stored = 'hi $token there';
      final ranges = computeMentionDisplayRanges(
        stored: stored,
        resolveParticipantName: resolveName,
        localIdentity: localId,
        everyoneName: 'everyone',
        unknownName: 'unknown',
      );

      expect(ranges.length, 1);
      expect(ranges.single.mentionId, otherId);
      expect(ranges.single.start, 3);
      expect(ranges.single.end, 3 + '@Alice Nguyen'.length);
    });
  });

  group('collapseMentionSpaceBeforePunctuation', () {
    test('removes space before comma after mention', () {
      const label = '@Alice Nguyen';
      final display = 'Morning $label , I';
      final ranges = [
        MentionDisplayRange(
          start: 'Morning '.length,
          end: 'Morning '.length + label.length,
          mentionId: otherId,
        ),
      ];

      final collapsed = collapseMentionSpaceBeforePunctuation(
        display,
        display.indexOf(',') + 1,
        ranges: ranges,
      );

      expect(collapsed?.text, 'Morning $label, I');
      expect(collapsed?.caret, display.indexOf(','));
    });

    test('ignores comma not preceded by mention space', () {
      const display = 'Morning, all';
      final collapsed = collapseMentionSpaceBeforePunctuation(
        display,
        display.indexOf(',') + 1,
        ranges: const [],
      );
      expect(collapsed, isNull);
    });
  });

  group('findActiveMentionQueryInDisplay', () {
    test('ignores @ inside a completed mention', () {
      final token = getMentionToken(otherId);
      final display = 'hi @Alice Nguyen ';
      final ranges = computeMentionDisplayRanges(
        stored: 'hi $token ',
        resolveParticipantName: resolveName,
        localIdentity: localId,
        everyoneName: 'everyone',
        unknownName: 'unknown',
      );

      expect(
        findActiveMentionQueryInDisplay(
          display,
          '@Alice Nguyen '.length,
          lockedRanges: ranges,
        ),
        isNull,
      );
    });

    test('detects a new @ query after a completed mention', () {
      final token = getMentionToken(otherId);
      final display = 'hi @Alice Nguyen @al';
      final ranges = computeMentionDisplayRanges(
        stored: 'hi $token @al',
        resolveParticipantName: resolveName,
        localIdentity: localId,
        everyoneName: 'everyone',
        unknownName: 'unknown',
      );

      final active = findActiveMentionQueryInDisplay(
        display,
        display.length,
        lockedRanges: ranges,
      );

      expect(active?.query, 'al');
    });
  });
}
