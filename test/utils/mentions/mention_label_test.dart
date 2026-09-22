import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/utils/mentions/mention_label.dart';
import 'package:meet/utils/mentions/mention_token.dart';
import 'package:meet/views/scenes/room/get_participant_display_colors.dart';
import 'package:meet/views/scenes/room/participant/participant_info.dart';
import 'package:mocktail/mocktail.dart';

class _MockParticipant extends Mock implements Participant {}

void main() {
  group('resolveParticipantColorIndex', () {
    test('uses roster index when identity is present', () {
      const firstId = 'aaaaaaaa-bbbb-4ccc-dddd-111111111111';
      const secondId = 'bbbbbbbb-bbbb-4ccc-dddd-222222222222';
      final first = _MockParticipant();
      final second = _MockParticipant();
      when(() => first.identity).thenReturn(firstId);
      when(() => second.identity).thenReturn(secondId);

      final tracks = [
        ParticipantInfo(participant: first, displayName: 'Alice'),
        ParticipantInfo(participant: second, displayName: 'Bob'),
      ];

      expect(
        resolveParticipantColorIndex(secondId, participantTracks: tracks),
        1,
      );
      expect(
        resolveParticipantColorIndex(firstId, participantTracks: tracks),
        0,
      );
    });

    test('falls back to hash when identity is not in roster', () {
      const identity = 'cccccccc-bbbb-4ccc-dddd-333333333333';
      expect(resolveParticipantColorIndex(identity), identity.hashCode);
    });

    test('everyone is handled separately in getMentionDisplayColors', () {
      expect(everyoneMentionColorIndex, 2);
      expect(everyoneMentionId, 'everyone');
    });
  });
}
