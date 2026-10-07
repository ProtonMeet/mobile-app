import 'package:flutter_test/flutter_test.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/views/scenes/room/reaction_stream/reaction_stream_layout.dart';

void main() {
  group('createReactionStreamItem', () {
    test('derives stable layout from identity and timestamp', () {
      final a = createReactionStreamItem(
        identity: 'user-a',
        emoji: '👍',
        timestamp: 42,
      );
      final b = createReactionStreamItem(
        identity: 'user-a',
        emoji: '👍',
        timestamp: 42,
      );

      expect(a.id, 'user-a-42');
      expect(b.leftPercent, a.leftPercent);
      expect(b.driftPx, a.driftPx);
      expect(b.riseVh, a.riseVh);
    });

    test('different timestamps get different horizontal positions', () {
      final first = createReactionStreamItem(
        identity: 'user-a',
        emoji: '❤️',
        timestamp: 1,
      );
      final second = createReactionStreamItem(
        identity: 'user-a',
        emoji: '❤️',
        timestamp: 2,
      );

      expect(first.id, isNot(second.id));
      expect(
        first.leftPercent == second.leftPercent &&
            first.driftPx == second.driftPx &&
            first.riseVh == second.riseVh,
        isFalse,
      );
    });
  });

  group('reactionStreamAppearOpacity', () {
    test('matches web keyframe endpoints', () {
      expect(reactionStreamAppearOpacity(0), 0);
      expect(reactionStreamAppearOpacity(0.06), closeTo(1, 0.001));
      expect(reactionStreamAppearOpacity(0.5), 1);
      expect(reactionStreamAppearOpacity(1), closeTo(0, 0.001));
    });
  });

  test('raised hand emoji constant is excluded at stream layer', () {
    expect(raisedHandEmoji, '🤚');
  });
}
