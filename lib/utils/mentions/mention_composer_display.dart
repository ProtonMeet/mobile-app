import 'package:flutter/material.dart';
import 'package:meet/utils/mentions/mention_label.dart';
import 'package:meet/utils/mentions/mention_token.dart';
import 'package:meet/views/scenes/room/participant/participant_info.dart';

/// Display-text range occupied by one completed `@mention` in the composer.
class MentionDisplayRange {
  const MentionDisplayRange({
    required this.start,
    required this.end,
    required this.mentionId,
  });

  final int start;

  /// Exclusive end; may include one atomic trailing space after the label.
  final int end;
  final String mentionId;

  bool containsCaret(int offset) => offset > start && offset <= end;

  bool containsAtSign(int atIndex) => atIndex >= start && atIndex < end;

  bool intersects(int changeStart, int changeEnd) =>
      changeStart < end && changeEnd > start;
}

/// Builds `@Name` display ranges from stored token text.
List<MentionDisplayRange> computeMentionDisplayRanges({
  required String stored,
  required String Function(String id) resolveParticipantName,
  required String localIdentity,
  required String everyoneName,
  required String unknownName,
}) {
  final ranges = <MentionDisplayRange>[];
  final segments = splitMessageIntoMentionSegments(stored);
  var offset = 0;

  for (var i = 0; i < segments.length; i++) {
    final segment = segments[i];
    if (segment is TextSegment) {
      offset += segment.text.length;
      continue;
    }

    final mention = segment as MentionSegment;
    final label =
        '@${getMentionLabel(mention.id, participantName: resolveParticipantName(mention.id), localIdentity: localIdentity, everyoneName: everyoneName, unknownName: unknownName)}';
    final start = offset;
    offset += label.length;
    var end = offset;

    if (i + 1 < segments.length) {
      final next = segments[i + 1];
      if (next is TextSegment && next.text.isNotEmpty && next.text[0] == ' ') {
        end += 1;
      }
    }

    ranges.add(
      MentionDisplayRange(start: start, end: end, mentionId: mention.id),
    );
  }

  return ranges;
}

/// Active `@` query at [caretOffset], ignoring completed [lockedRanges].
({int atIndex, String query})? findActiveMentionQueryInDisplay(
  String displayText,
  int caretOffset, {
  Iterable<MentionDisplayRange> lockedRanges = const [],
}) {
  if (caretOffset < 0 || caretOffset > displayText.length) {
    return null;
  }

  for (final range in lockedRanges) {
    if (range.containsCaret(caretOffset)) {
      return null;
    }
  }

  final prefix = displayText.substring(0, caretOffset);
  final atIndex = prefix.lastIndexOf('@');
  if (atIndex < 0) {
    return null;
  }

  for (final range in lockedRanges) {
    if (range.containsAtSign(atIndex)) {
      return null;
    }
  }

  final match = RegExp(
    r'^@([^\s][^\n]{0,75}|)$',
  ).firstMatch(prefix.substring(atIndex));
  if (match == null) {
    return null;
  }

  return (atIndex: atIndex, query: match.group(1)!);
}

/// Inline spans for the composer mirror layer (same colors as sent messages).
TextSpan buildComposerMentionTextSpan({
  required BuildContext context,
  required String stored,
  required TextStyle baseStyle,
  required String Function(String id) resolveParticipantName,
  required String localIdentity,
  required String everyoneName,
  required String unknownName,
  required List<ParticipantInfo>? participantTracks,
}) {
  final segments = splitMessageIntoMentionSegments(stored);
  if (segments.every((segment) => segment is TextSegment)) {
    return TextSpan(text: stored, style: baseStyle);
  }

  final children = <InlineSpan>[];
  for (final segment in segments) {
    if (segment is MentionSegment) {
      final label = getMentionLabel(
        segment.id,
        participantName: resolveParticipantName(segment.id),
        localIdentity: localIdentity,
        everyoneName: everyoneName,
        unknownName: unknownName,
      );
      final colors = getMentionDisplayColors(
        context,
        segment.id,
        participantTracks: participantTracks,
      );
      children.add(
        TextSpan(
          text: '@$label',
          style: baseStyle.copyWith(
            color: colors.profileTextColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      continue;
    }

    final text = (segment as TextSegment).text;
    if (text.isNotEmpty) {
      children.add(TextSpan(text: text, style: baseStyle));
    }
  }

  return TextSpan(children: children);
}
