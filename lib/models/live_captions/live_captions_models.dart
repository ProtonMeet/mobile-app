import 'package:equatable/equatable.dart';

/// UI state for the caption bar.
enum CaptionsStatus {
  /// Handler registered; no segments yet; not failing.
  loading,

  /// Agent present and listening; zero segments received.
  ready,

  /// At least one caption segment is available to render.
  active,

  /// Streams received but none could be decrypted (stalled feed).
  failing,
}

/// One logical caption fragment after MLS decrypt (before merge / slice).
class CaptionSegment extends Equatable {
  const CaptionSegment({
    required this.id,
    required this.text,
    required this.speakerIdentity,
    required this.isFinal,
    required this.receivedAtMs,
  });

  /// `lk.segment_id`, stream id fallback, or client-generated key.
  final String id;

  /// Decrypted plaintext from `decryptMessage().message` — only field shown.
  final String text;

  /// LiveKit participant identity resolved from `lk.transcribed_track_id`.
  /// Empty when unresolved (no speaker label, no merge).
  final String speakerIdentity;

  /// Whether `lk.transcription_final === 'true'`.
  final bool isFinal;

  /// Client clock when the segment was stored (`Date.now()` on web).
  final int receivedAtMs;

  CaptionSegment copyWith({
    String? id,
    String? text,
    String? speakerIdentity,
    bool? isFinal,
    int? receivedAtMs,
  }) {
    return CaptionSegment(
      id: id ?? this.id,
      text: text ?? this.text,
      speakerIdentity: speakerIdentity ?? this.speakerIdentity,
      isFinal: isFinal ?? this.isFinal,
      receivedAtMs: receivedAtMs ?? this.receivedAtMs,
    );
  }

  @override
  List<Object?> get props => [id, text, speakerIdentity, isFinal, receivedAtMs];
}

/// Output of the transcription pipeline consumed by the caption overlay.
class Transcriptions extends Equatable {
  const Transcriptions({required this.segments, required this.status});

  /// Merged lines after gap/length rules, oldest first, sliced to the newest
  /// `LiveCaptionsConstants.maxTranscriptLines`.
  final List<CaptionSegment> segments;
  final CaptionsStatus status;

  static const empty = Transcriptions(
    segments: [],
    status: CaptionsStatus.loading,
  );

  @override
  List<Object?> get props => [segments, status];
}

/// Internal counters for stalled-feed / failing detection (not shown in UI).
class TranscriptionDiagnostics {
  TranscriptionDiagnostics({
    this.streamsReceived = 0,
    this.streamReadFailures = 0,
    this.decryptFailures = 0,
  });

  int streamsReceived;
  int streamReadFailures;
  int decryptFailures;

  TranscriptionDiagnostics copyWith({
    int? streamsReceived,
    int? streamReadFailures,
    int? decryptFailures,
  }) {
    return TranscriptionDiagnostics(
      streamsReceived: streamsReceived ?? this.streamsReceived,
      streamReadFailures: streamReadFailures ?? this.streamReadFailures,
      decryptFailures: decryptFailures ?? this.decryptFailures,
    );
  }
}

/// Ephemeral merge result (not persisted).
class MergedCaptionLine extends Equatable {
  const MergedCaptionLine({required this.line, required this.memberIds});

  /// Combined segment; [CaptionSegment.text] holds merged plaintext.
  final CaptionSegment line;

  /// Original segment ids kept alive for expiry pinning.
  final List<String> memberIds;

  @override
  List<Object?> get props => [line, memberIds];
}

/// Result of `AppCore.decryptMessage` on a transcription payload.
class DecryptedCaptionMessage extends Equatable {
  const DecryptedCaptionMessage({
    required this.message,
    required this.senderParticipantId,
  });

  /// Plaintext caption — becomes [CaptionSegment.text].
  final String message;

  /// MLS sender id from decrypt; captions UI uses track-based speaker instead.
  final String senderParticipantId;

  /// Maps FRB `(message, senderParticipantId)` tuple from [AppCore.decryptMessage].
  factory DecryptedCaptionMessage.fromRecord((String, String) record) {
    final (message, senderParticipantId) = record;
    return DecryptedCaptionMessage(
      message: message,
      senderParticipantId: senderParticipantId,
    );
  }

  @override
  List<Object?> get props => [message, senderParticipantId];
}

/// REST `AgentType` for `POST .../agents` (closed captions / STT).
enum LiveCaptionAgentType {
  closedCaptions(1);

  const LiveCaptionAgentType(this.apiValue);
  final int apiValue;
}

/// Derives [CaptionsStatus] using the same precedence as web `useTranscriptions`.
CaptionsStatus deriveCaptionsStatus({
  required bool hasSegments,
  required bool failing,
  required bool listening,
  required bool agentPresent,
}) {
  if (hasSegments) {
    return CaptionsStatus.active;
  }
  if (failing) {
    return CaptionsStatus.failing;
  }
  if (listening && agentPresent) {
    return CaptionsStatus.ready;
  }
  return CaptionsStatus.loading;
}
