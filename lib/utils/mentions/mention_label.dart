import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/utils/mentions/mention_token.dart';
import 'package:meet/views/scenes/room/get_participant_display_colors.dart';
import 'package:meet/views/scenes/room/participant/participant_info.dart';

/// Resolves the `@` label shown for a mention id.
String getMentionLabel(
  String id, {
  required String? participantName,
  required String localIdentity,
  required String everyoneName,
  required String unknownName,
}) {
  if (id == everyoneMentionId) {
    return everyoneName;
  }
  if (id == localIdentity) {
    final trimmed = participantName?.trim() ?? '';
    if (trimmed.isNotEmpty && trimmed != localIdentity) {
      return trimmed;
    }
  }
  final trimmed = participantName?.trim() ?? '';
  if (trimmed.isNotEmpty && trimmed != id) {
    return trimmed;
  }
  return unknownName;
}

/// Color index used for `@everyone` mentions (web palette index 2).
const int everyoneMentionColorIndex = 2;

/// Text color for inline `@mention` chips (not roster avatar colors).
Color getMentionTextColor(
  BuildContext context,
  String id, {
  required String localIdentity,
}) {
  final colors = context.colors;
  if (id == localIdentity) {
    return colors.greenInteractionNormMajor1;
  }
  return colors.interActionNormMajor1;
}

/// Avatar colors for mention suggestion rows (roster / `@everyone` palette).
ParticipantDisplayColors getMentionDisplayColors(
  BuildContext context,
  String id, {
  List<ParticipantInfo>? participantTracks,
}) {
  if (id == everyoneMentionId) {
    return getParticipantDisplayColors(context, everyoneMentionColorIndex);
  }
  return getParticipantAvatarColors(
    context,
    id,
    participantTracks: participantTracks,
  );
}

/// Builds a participant id → display name map from the roster.
Map<String, String> buildParticipantNameMap(
  List<ParticipantInfo>? participantTracks,
) {
  if (participantTracks == null) {
    return const {};
  }
  return {
    for (final info in participantTracks)
      if (info.participant.identity.isNotEmpty)
        info.participant.identity: info.displayName,
  };
}
