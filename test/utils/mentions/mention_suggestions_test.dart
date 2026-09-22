import 'package:flutter_test/flutter_test.dart';
import 'package:meet/utils/mentions/mention_suggestions.dart';

void main() {
  group('normalizeMentionQuery', () {
    test('lowercases and strips accents for matching', () {
      expect(normalizeMentionQuery('José'), 'jose');
      expect(normalizeMentionQuery('AL'), 'al');
    });
  });
}
