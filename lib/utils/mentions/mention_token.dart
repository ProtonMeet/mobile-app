/// Wire-format helpers for chat @mentions.
///
/// Stored message text embeds opaque tokens; UI expands them to `@DisplayName`.
library;

/// Room-wide mention id inside a token.
const String everyoneMentionId = 'everyone';

/// Maximum stored characters for a single chat message.
const int chatMessageMaxLength = 2048;

/// Show the character counter once stored length reaches this fraction of the max.
const double chatMessageLengthWarningRatio = 0.9;

/// Strict mention token pattern — malformed tokens stay plain text.
final RegExp mentionTokenRegex = RegExp(
  r'\[participant_uuid:(everyone|[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\]',
);

/// Builds the stored token for a participant id or [everyoneMentionId].
String getMentionToken(String id) => '[participant_uuid:$id]';

/// Detects an active `@` query at the caret for typeahead.
///
/// Pattern: `(?:^|\s)@([^\s][^\n]{0,75}|)$`
final RegExp mentionQueryRegex = RegExp(r'(?:^|\s)@([^\s][^\n]{0,75}|)$');

/// A parsed mention segment from stored message text.
class MentionSegment {
  const MentionSegment({required this.id, required this.rawToken});

  final String id;
  final String rawToken;
}

/// A plain-text segment from stored message text.
class TextSegment {
  const TextSegment(this.text);

  final String text;
}

/// Splits stored message text into alternating text and mention segments.
List<Object> splitMessageIntoMentionSegments(String message) {
  final segments = <Object>[];
  var lastEnd = 0;

  for (final match in mentionTokenRegex.allMatches(message)) {
    if (match.start > lastEnd) {
      segments.add(TextSegment(message.substring(lastEnd, match.start)));
    }
    segments.add(
      MentionSegment(id: match.group(1)!, rawToken: match.group(0)!),
    );
    lastEnd = match.end;
  }

  if (lastEnd < message.length) {
    segments.add(TextSegment(message.substring(lastEnd)));
  }

  return segments;
}

/// Whether [message] mentions [localIdentity] directly or via `@everyone`.
bool isParticipantMentioned(String message, String localIdentity) {
  if (localIdentity.isEmpty) {
    return false;
  }
  for (final segment in splitMessageIntoMentionSegments(message)) {
    if (segment is! MentionSegment) {
      continue;
    }
    if (segment.id == localIdentity || segment.id == everyoneMentionId) {
      return true;
    }
  }
  return false;
}

/// Extracts ordered mention ids from stored message text.
List<String> extractMentionIds(String message) {
  return [
    for (final segment in splitMessageIntoMentionSegments(message))
      if (segment is MentionSegment) segment.id,
  ];
}

/// Active `@` query at [caretOffset] in [displayText], if any.
({int atIndex, String query})? findActiveMentionQuery(
  String displayText,
  int caretOffset,
) {
  if (caretOffset < 0 || caretOffset > displayText.length) {
    return null;
  }
  final prefix = displayText.substring(0, caretOffset);
  final atIndex = prefix.lastIndexOf('@');
  if (atIndex < 0) {
    return null;
  }
  final match = RegExp(
    r'^@([^\s][^\n]{0,75}|)$',
  ).firstMatch(prefix.substring(atIndex));
  if (match == null) {
    return null;
  }
  return (atIndex: atIndex, query: match.group(1)!);
}
