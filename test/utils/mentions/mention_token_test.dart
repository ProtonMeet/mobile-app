import 'package:flutter_test/flutter_test.dart';
import 'package:meet/utils/mentions/mention_token.dart';

void main() {
  const localId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  const otherId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

  group('splitMessageIntoMentionSegments', () {
    test('plain text becomes a single text segment', () {
      final segments = splitMessageIntoMentionSegments('hello world');
      expect(segments.length, 1);
      expect((segments.single as TextSegment).text, 'hello world');
    });

    test('valid uuid token becomes a mention segment', () {
      final token = getMentionToken(otherId);
      final segments = splitMessageIntoMentionSegments('hi $token there');
      expect(segments.length, 3);
      expect((segments[0] as TextSegment).text, 'hi ');
      expect((segments[1] as MentionSegment).id, otherId);
      expect((segments[2] as TextSegment).text, ' there');
    });

    test('malformed tokens stay plain text', () {
      const malformed = '[participant_uuid:not-a-uuid]';
      final segments = splitMessageIntoMentionSegments(malformed);
      expect(segments.length, 1);
      expect((segments.single as TextSegment).text, malformed);
    });
  });

  group('isParticipantMentioned', () {
    test('detects direct mention', () {
      final token = getMentionToken(localId);
      expect(isParticipantMentioned('hi $token', localId), isTrue);
    });

    test('detects everyone mention', () {
      final token = getMentionToken(everyoneMentionId);
      expect(isParticipantMentioned('hi $token', localId), isTrue);
    });

    test('ignores mentions of other participants', () {
      final token = getMentionToken(otherId);
      expect(isParticipantMentioned('hi $token', localId), isFalse);
    });
  });
}
