import 'package:flutter_test/flutter_test.dart';
import 'package:meet/helper/meet_join_link_parser.dart';

void main() {
  const myDomain = 'xxx.proton.xxxx';
  group('parseMeetJoinLink', () {
    test('supports join/guest/u/<any> paths with #pwd fragment', () {
      const cases = [
        (
          'https://xxx.proton.xxxx/join/id-TESTROOM123#pwd-TESTPWD123456',
          'TESTROOM123',
          'TESTPWD123456',
        ),
        (
          'https://xxx.proton.xxxx/guest/join/id-TESTROOM123#pwd-TESTPWD123456',
          'TESTROOM123',
          'TESTPWD123456',
        ),
        (
          'https://xxx.proton.xxxx/u/any/join/id-TESTROOM123#pwd-TESTPWD123456',
          'TESTROOM123',
          'TESTPWD123456',
        ),
        (
          'https://xxx.proton.xxxx/u/guest/join/id-TESTROOM123#pwd-TESTPWD123456',
          'TESTROOM123',
          'TESTPWD123456',
        ),
        (
          'https://xxx.proton.xxxx/u/123456/join/id-TESTROOM123#pwd-TESTPWD123456',
          'TESTROOM123',
          'TESTPWD123456',
        ),
        (
          'https://xxx.proton.xxxx/join/id-ROOMABCDEF9#pwd-PWDABCDEF9999',
          'ROOMABCDEF9',
          'PWDABCDEF9999',
        ),
        (
          'https://xxx.proton.xxxx/u/43/join/id-ROOMABCDEF9#pwd-PWDABCDEF9999X',
          'ROOMABCDEF9',
          'PWDABCDEF9999X',
        ),
      ];

      for (final c in cases) {
        final result = parseMeetJoinLink(c.$1, allowedHost: myDomain);
        expect(result.isHttpUrl, isTrue, reason: c.$1);
        expect(result.isAllowedHost, isTrue, reason: c.$1);
        expect(result.roomId, c.$2, reason: c.$1);
        expect(result.passcode, c.$3, reason: c.$1);
        expect(result.isValid, isTrue, reason: c.$1);
      }
    });

    test('supports ?pwd query fallback', () {
      const url =
          'https://xxx.proton.xxxx/join/id-TESTROOM123?pwd=TESTPWD123456';
      final result = parseMeetJoinLink(url, allowedHost: myDomain);
      expect(result.roomId, 'TESTROOM123');
      expect(result.passcode, 'TESTPWD123456');
      expect(result.isValid, isTrue);
    });

    test('supports URL-encoded fragment fallback (%23pwd-...)', () {
      const url =
          'https://xxx.proton.xxxx/join/id-TESTROOM123%23pwd-TESTPWD123456';
      final result = parseMeetJoinLink(url, allowedHost: myDomain);
      expect(result.roomId, 'TESTROOM123');
      expect(result.passcode, 'TESTPWD123456');
      expect(result.isValid, isTrue);
    });

    test('invalid host is rejected', () {
      const url = 'https://example.com/join/id-4FZ53S92E4#pwd-vaEjaD5jE6fJ';
      final result = parseMeetJoinLink(url);
      expect(result.isHttpUrl, isTrue);
      expect(result.isAllowedHost, isFalse);
      expect(result.isValid, isFalse);
    });

    test('missing pwd still parses room id', () {
      const url = 'https://xxx.proton.xxxx/join/id-TESTROOM123';
      final result = parseMeetJoinLink(url, allowedHost: myDomain);
      expect(result.isAllowedHost, isTrue);
      expect(result.roomId, 'TESTROOM123');
      expect(result.passcode, isNull);
      // Passcode is required for a link to be considered valid.
      expect(result.isValid, isFalse);
    });

    test('invalid fragment prefix does not parse passcode', () {
      const url =
          'https://xxx.proton.xxxx/u/43/join/id-NFF3PVTV44#11pw-fKpmYAPVI21e';
      final result = parseMeetJoinLink(url, allowedHost: myDomain);
      expect(result.isAllowedHost, isTrue);
      expect(result.roomId, 'NFF3PVTV44');
      expect(result.passcode, isNull);
      expect(result.isValid, isFalse);
    });

    test('rejects passcode with special characters', () {
      const url = 'https://xxx.proton.xxxx/join/id-TESTROOM#pwd-test@123';
      final result = parseMeetJoinLink(url, allowedHost: myDomain);
      expect(result.passcode, isNull);
      expect(result.isValid, isFalse);
    });

    test('handles excessively long room id safely', () {
      final longId = 'A' * 10000;
      final url = 'https://xxx.proton.xxxx/join/id-$longId#pwd-pass';
      final result = parseMeetJoinLink(url, allowedHost: myDomain);
      // Should handle without crashing
      expect(result.roomId, longId);
    });
  });
}
