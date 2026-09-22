import 'package:meet/utils/mentions/mention_label.dart';
import 'package:meet/utils/mentions/mention_token.dart';

/// Replaces mention tokens with `@Name` for search, a11y, and notifications.
String mentionPlainText(
  String message, {
  required Map<String, String> participantNameMap,
  required String localIdentity,
  required String everyoneName,
  required String unknownName,
}) {
  final buffer = StringBuffer();
  for (final segment in splitMessageIntoMentionSegments(message)) {
    if (segment is TextSegment) {
      buffer.write(segment.text);
      continue;
    }
    final mention = segment as MentionSegment;
    final label = getMentionLabel(
      mention.id,
      participantName: participantNameMap[mention.id],
      localIdentity: localIdentity,
      everyoneName: everyoneName,
      unknownName: unknownName,
    );
    buffer.write('@$label');
  }
  return buffer.toString();
}
