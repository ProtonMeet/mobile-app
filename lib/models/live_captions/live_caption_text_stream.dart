import 'dart:convert';

import 'package:livekit_client/livekit_client.dart';
import 'package:meet/constants/live_captions_constants.dart';
import 'package:meet/helper/extension/live_caption_participant_attributes.dart';
import 'package:meet/models/live_captions/live_caption_agent.dart';
import 'package:meet/models/live_captions/live_captions_models.dart';

/// Parsed LiveKit transcription stream attributes for one chunk.
class TranscriptionStreamAttributes {
  const TranscriptionStreamAttributes({
    required this.segmentId,
    required this.isFinal,
    required this.transcribedTrackId,
  });

  final String segmentId;
  final bool isFinal;
  final String transcribedTrackId;

  factory TranscriptionStreamAttributes.fromMap(
    Map<String, String> attributes,
  ) {
    return TranscriptionStreamAttributes(
      segmentId: attributes[LiveCaptionsConstants.segmentIdAttr] ?? '',
      isFinal: LiveCaptionsConstants.parseTranscriptionFinal(
        attributes[LiveCaptionsConstants.transcriptionFinalAttr],
      ),
      transcribedTrackId:
          attributes[LiveCaptionsConstants.transcribedTrackIdAttr] ?? '',
    );
  }
}

/// Decodes the concatenated text-stream payload (`base64` MLS ciphertext).
List<int> decodeTranscriptionPayload(String base64Payload) =>
    base64Decode(base64Payload);

/// Whether transcription streams from [participant] should be processed.
bool isTranscriptionStreamSender(Participant participant) =>
    isCaptionAgent(participant);

/// Resolves speaker LiveKit identity from `lk.transcribed_track_id`.
///
/// Returns empty string when [trackSid] is missing or no publication matches.
String resolveSpeakerIdentityForTranscribedTrack(Room room, String? trackSid) {
  if (trackSid == null || trackSid.isEmpty) {
    return '';
  }
  for (final participant in room.allParticipants) {
    for (final publication in participant.trackPublications.values) {
      if (publication.sid == trackSid || publication.track?.sid == trackSid) {
        return participant.identity;
      }
    }
  }
  return '';
}

/// Builds a [CaptionSegment] from decrypt output and stream metadata.
CaptionSegment buildCaptionSegment({
  required DecryptedCaptionMessage decrypted,
  required TranscriptionStreamAttributes streamAttributes,
  required Room room,
  required String fallbackSegmentId,
  int? receivedAtMs,
}) {
  final speakerIdentity = resolveSpeakerIdentityForTranscribedTrack(
    room,
    streamAttributes.transcribedTrackId,
  );
  final segmentId = streamAttributes.segmentId.isNotEmpty
      ? streamAttributes.segmentId
      : fallbackSegmentId;

  return CaptionSegment(
    id: segmentId,
    text: decrypted.message,
    speakerIdentity: speakerIdentity,
    isFinal: streamAttributes.isFinal,
    receivedAtMs: receivedAtMs ?? DateTime.now().millisecondsSinceEpoch,
  );
}
