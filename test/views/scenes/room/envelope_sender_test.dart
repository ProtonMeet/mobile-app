import 'package:flutter_test/flutter_test.dart';
import 'package:meet/views/scenes/room/envelope_sender.dart';

void main() {
  group('claimedParticipantIdFromEnvelope', () {
    void expectClaimed(Map<String, dynamic> json, Object? matcher) {
      expect(claimedParticipantIdFromEnvelope(json), matcher);
    }

    test('parses identity when id suffix matches timestamp', () {
      expectClaimed({
        'id': 'user-abc-1730000000123',
        'timestamp': 1730000000123,
      }, 'user-abc');
    });

    test('returns null when timestamp suffix does not match id', () {
      expectClaimed({
        'id': 'user-abc-1730000000123',
        'timestamp': 999,
      }, isNull);
    });

    test('returns null when id is missing', () {
      expectClaimed({
        'timestamp': 1730000000123,
      }, isNull);
    });

    test('returns null when timestamp is missing', () {
      expectClaimed({
        'id': 'x-1',
      }, isNull);
    });

    test('accepts timestamp as string of int', () {
      expectClaimed({
        'id': 'pid-42',
        'timestamp': '42',
      }, 'pid');
    });

    test('returns null when id is not a string', () {
      expectClaimed({
        'id': 123,
        'timestamp': 1,
      }, isNull);
    });

    test('returns null when claimed identity would be empty', () {
      expectClaimed({
        'id': '-1730000000123',
        'timestamp': 1730000000123,
      }, isNull);
    });

    test('uses truncated millis for num timestamp', () {
      expectClaimed({
        'id': 'x-100',
        'timestamp': 100.9,
      }, 'x');
    });
  });
}
