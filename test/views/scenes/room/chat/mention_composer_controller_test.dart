import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meet/utils/mentions/mention_token.dart';
import 'package:meet/views/scenes/room/chat/mention_composer_controller.dart';

void main() {
  const localId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  const aliceId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

  MentionComposerController createController({String initialStored = ''}) {
    return MentionComposerController(
      resolveParticipantName: (id) => id == aliceId ? 'Alice' : id,
      everyoneName: 'everyone',
      unknownName: 'unknown',
      localIdentity: localId,
      initialStored: initialStored,
    );
  }

  group('MentionComposerController.formatEditUpdate', () {
    test('replaces a selection spanning a mention with typed text', () {
      final token = getMentionToken(aliceId);
      final controller = createController(initialStored: '$token hello there');
      final formatter = MentionComposerTextInputFormatter(controller);

      final oldValue = TextEditingValue(
        text: controller.displayController.text,
        selection: TextSelection(
          baseOffset: 0,
          extentOffset: controller.displayController.text.length,
        ),
      );
      final newValue = oldValue.copyWith(
        text: 'x',
        selection: const TextSelection.collapsed(offset: 1),
      );

      final result = formatter.formatEditUpdate(oldValue, newValue);

      expect(result.text, 'x');
      expect(controller.storedText, 'x');
    });

    test('replaces select-all content over multiple mentions', () {
      final token = getMentionToken(aliceId);
      final controller = createController(initialStored: '$token $token hi');
      final formatter = MentionComposerTextInputFormatter(controller);

      final oldValue = TextEditingValue(
        text: controller.displayController.text,
        selection: TextSelection(
          baseOffset: 0,
          extentOffset: controller.displayController.text.length,
        ),
      );
      const replacement = 'new message';
      final newValue = oldValue.copyWith(
        text: replacement,
        selection: TextSelection.collapsed(offset: replacement.length),
      );

      final result = formatter.formatEditUpdate(oldValue, newValue);

      expect(result.text, replacement);
      expect(controller.storedText, replacement);
    });
  });

  group('MentionComposerController punctuation', () {
    test('removes trailing space when typing comma after mention', () {
      final token = getMentionToken(aliceId);
      final controller = createController(initialStored: 'Morning $token ');
      final formatter = MentionComposerTextInputFormatter(controller);

      final oldText = controller.displayController.text;
      expect(oldText, 'Morning @Alice ');

      final newText = 'Morning @Alice ,';
      final newValue = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
      final oldValue = TextEditingValue(
        text: oldText,
        selection: TextSelection.collapsed(offset: oldText.length),
      );

      final result = formatter.formatEditUpdate(oldValue, newValue);

      expect(result.text, 'Morning @Alice,');
      expect(controller.storedText, 'Morning $token,');
    });
  });

  group('MentionComposerController rebuild', () {
    test('keeps a literal @Name before a real mention', () {
      final token = getMentionToken(aliceId);
      final controller = createController(initialStored: '$token');

      controller.displayController.text = '@Alice @Alice ';

      expect(controller.storedText, '@Alice $token ');
    });
  });
}
