import 'package:flutter_test/flutter_test.dart';
import 'package:meet/utils/mentions/mention_suggestions.dart';
import 'package:meet/utils/mentions/mention_token.dart';

void main() {
  group('defaultMentionSuggestionHighlightIndex', () {
    test('skips @everyone and highlights first participant', () {
      const suggestions = [
        MentionSuggestion(
          id: everyoneMentionId,
          name: 'everyone',
          isEveryone: true,
        ),
        MentionSuggestion(id: 'a', name: 'Alice'),
        MentionSuggestion(id: 'b', name: 'Bob'),
      ];
      expect(defaultMentionSuggestionHighlightIndex(suggestions), 1);
    });

    test('uses index 0 when everyone is not in the list', () {
      const suggestions = [MentionSuggestion(id: 'a', name: 'Alice')];
      expect(defaultMentionSuggestionHighlightIndex(suggestions), 0);
    });
  });

  group('normalizeMentionQuery', () {
    test('lowercases and strips accents for matching', () {
      expect(normalizeMentionQuery('José'), 'jose');
      expect(normalizeMentionQuery('AL'), 'al');
    });

    test('folds extended latin used in participant names', () {
      expect(normalizeMentionQuery('Maćko'), 'macko');
      expect(normalizeMentionQuery('ÿ'), 'y');
      expect(normalizeMentionQuery('Straße'), 'strasse');
    });
  });
}
