import 'package:meet/utils/mentions/mention_token.dart';
import 'package:meet/views/scenes/room/participant/participant_info.dart';

/// One row in the `@` suggestion list.
class MentionSuggestion {
  const MentionSuggestion({
    required this.id,
    required this.name,
    this.isEveryone = false,
  });

  final String id;
  final String name;
  final bool isEveryone;
}

const Map<String, String> _accentFoldings = {
  'àáâãäå': 'a',
  'òóôõöø': 'o',
  'èéêë': 'e',
  'ìíîï': 'i',
  'ùúûü': 'u',
  'ýÿ': 'y',
  'ç': 'c',
  'ñ': 'n',
  'ß': 'ss',
  'š': 's',
  'ž': 'z',
  'ł': 'l',
  'āăą': 'a',
  'ćĉċč': 'c',
  'ďđ': 'd',
  'ēĕėęě': 'e',
  'ĝğ': 'g',
};

final Map<int, String> _accentFoldByRune = _buildAccentFoldByRune();

Map<int, String> _buildAccentFoldByRune() {
  final map = <int, String>{};
  for (final entry in _accentFoldings.entries) {
    for (final codeUnit in entry.key.codeUnits) {
      map[codeUnit] = entry.value;
    }
  }
  return map;
}

String normalizeMentionQuery(String value) {
  final lower = value.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    buffer.write(_accentFoldByRune[rune] ?? String.fromCharCode(rune));
  }
  return buffer.toString();
}

bool _matchesMentionQuery(String candidate, String normalizedQuery) {
  if (normalizedQuery.isEmpty) {
    return true;
  }
  return normalizeMentionQuery(candidate).contains(normalizedQuery);
}

/// Builds and filters the mention suggestion list.
List<MentionSuggestion> getMentionSuggestions({
  required List<ParticipantInfo>? participantTracks,
  required String localIdentity,
  required String everyoneName,
  String everyoneHint = '',
  String query = '',
}) {
  final others = <MentionSuggestion>[];
  if (participantTracks != null) {
    for (final info in participantTracks) {
      final identity = info.participant.identity;
      if (identity.isEmpty || identity == localIdentity) {
        continue;
      }
      final name = info.displayName.trim();
      if (name.isEmpty || name == identity) {
        continue;
      }
      others.add(MentionSuggestion(id: identity, name: name));
    }
  }

  if (others.isEmpty) {
    return const [];
  }

  final normalizedQuery = normalizeMentionQuery(query.trim());

  final suggestions = <MentionSuggestion>[
    if (_matchesMentionQuery(everyoneName, normalizedQuery) ||
        _matchesMentionQuery(everyoneHint, normalizedQuery))
      MentionSuggestion(
        id: everyoneMentionId,
        name: everyoneName,
        isEveryone: true,
      ),
    ...others.where(
      (suggestion) => _matchesMentionQuery(suggestion.name, normalizedQuery),
    ),
  ];

  return suggestions;
}

/// Index of the suggestion row highlighted by default (first participant, not `@everyone`).
int defaultMentionSuggestionHighlightIndex(
  List<MentionSuggestion> suggestions,
) {
  if (suggestions.isEmpty) {
    return -1;
  }
  final firstParticipant = suggestions.indexWhere((s) => !s.isEveryone);
  if (firstParticipant >= 0) {
    return firstParticipant;
  }
  return 0;
}
