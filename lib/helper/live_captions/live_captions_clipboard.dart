import 'package:meet/models/live_captions/live_captions_models.dart';
import 'package:meet/rust/proton_meet/models/meet_participant.dart';

/// Plain-text export for copying live captions to the clipboard.
String formatLiveCaptionsForClipboard({
  required List<CaptionSegment> segments,
  required Map<String, MeetParticipant> participantNamesByIdentity,
}) {
  if (segments.isEmpty) {
    return '';
  }

  final buffer = StringBuffer();
  for (final segment in segments) {
    if (buffer.isNotEmpty) {
      buffer.writeln();
    }
    final speakerName = _speakerName(
      segment.speakerIdentity,
      participantNamesByIdentity,
    );
    if (speakerName != null) {
      buffer.write('$speakerName: ${segment.text}');
    } else {
      buffer.write(segment.text);
    }
  }
  return buffer.toString();
}

String? _speakerName(
  String speakerIdentity,
  Map<String, MeetParticipant> participantNamesByIdentity,
) {
  if (speakerIdentity.isEmpty) {
    return null;
  }
  final displayName = participantNamesByIdentity[speakerIdentity]?.displayName
      ?.trim();
  if (displayName != null && displayName.isNotEmpty) {
    return displayName;
  }
  return speakerIdentity;
}
