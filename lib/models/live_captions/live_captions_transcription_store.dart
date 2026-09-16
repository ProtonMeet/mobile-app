import 'package:meet/constants/live_captions_constants.dart';
import 'package:meet/models/live_captions/live_captions_models.dart';

/// In-memory caption segment map with merge, expiry pinning, and UI snapshot.
class LiveCaptionsTranscriptionStore {
  final Map<String, CaptionSegment> _segments = {};

  /// Full session history; never pruned until [clear].
  final Map<String, CaptionSegment> _historySegments = {};

  bool get isEmpty => _segments.isEmpty;

  bool get historyIsEmpty => _historySegments.isEmpty;

  int get segmentCount => _segments.length;

  void upsert(CaptionSegment segment) {
    _segments[segment.id] = segment;
    _historySegments[segment.id] = segment;
  }

  void clear() {
    _segments.clear();
    _historySegments.clear();
  }

  /// All merged caption lines for the session, oldest first (no UI line cap).
  List<CaptionSegment> historyMergedSegments() {
    return _mergeSorted(
      _historySegments.values.toList(),
    ).map((line) => line.line).toList();
  }

  /// Member segment ids currently visible, kept alive until they scroll off.
  Set<String> pinnedMemberIds() {
    final merged = _mergeSorted(_segments.values.toList());
    if (merged.isEmpty) {
      return {};
    }
    return _visibleLines(merged).expand((line) => line.memberIds).toSet();
  }

  /// Drops expired segments except those in [pinnedIds].
  void pruneExpired({required int nowMs, required Set<String> pinnedIds}) {
    final finalLingerMs = LiveCaptionsConstants.finalLinger.inMilliseconds;
    final staleMs = LiveCaptionsConstants.staleSegment.inMilliseconds;

    _segments.removeWhere((id, segment) {
      if (pinnedIds.contains(id)) {
        return false;
      }
      final ageMs = nowMs - segment.receivedAtMs;
      if (segment.isFinal) {
        return ageMs > finalLingerMs;
      }
      return ageMs > staleMs;
    });
  }

  /// Builds merged visible lines and [CaptionsStatus] for the caption bar.
  Transcriptions snapshot({
    required int nowMs,
    required bool failing,
    required bool listening,
    required bool agentPresent,
  }) {
    final pinned = pinnedMemberIds();
    pruneExpired(nowMs: nowMs, pinnedIds: pinned);

    final merged = _mergeSorted(_segments.values.toList());
    final segments = _visibleLines(merged).map((line) => line.line).toList();

    return Transcriptions(
      segments: segments,
      status: deriveCaptionsStatus(
        hasSegments: segments.isNotEmpty,
        failing: failing,
        listening: listening,
        agentPresent: agentPresent,
      ),
    );
  }

  /// Newest [LiveCaptionsConstants.maxTranscriptLines] lines, oldest first.
  List<MergedCaptionLine> _visibleLines(List<MergedCaptionLine> merged) {
    final startIndex = merged.length > LiveCaptionsConstants.maxTranscriptLines
        ? merged.length - LiveCaptionsConstants.maxTranscriptLines
        : 0;
    return merged.sublist(startIndex);
  }

  List<MergedCaptionLine> _mergeSorted(List<CaptionSegment> segments) {
    final sorted = List<CaptionSegment>.from(segments)
      ..sort((a, b) => a.receivedAtMs.compareTo(b.receivedAtMs));

    final merged = <MergedCaptionLine>[];
    final mergeGapMs = LiveCaptionsConstants.mergeGap.inMilliseconds;

    for (final segment in sorted) {
      if (merged.isNotEmpty) {
        final previous = merged.last;
        final gapMs = segment.receivedAtMs - previous.line.receivedAtMs;
        final sameSpeaker =
            segment.speakerIdentity.isNotEmpty &&
            segment.speakerIdentity == previous.line.speakerIdentity;
        final combinedLength = previous.line.text.length + segment.text.length;

        if (sameSpeaker &&
            gapMs <= mergeGapMs &&
            combinedLength <= LiveCaptionsConstants.maxMergedLength) {
          merged[merged.length - 1] = MergedCaptionLine(
            line: previous.line.copyWith(
              text: '${previous.line.text}${segment.text}',
              isFinal: segment.isFinal,
              receivedAtMs: segment.receivedAtMs,
            ),
            memberIds: [...previous.memberIds, segment.id],
          );
          continue;
        }
      }

      merged.add(MergedCaptionLine(line: segment, memberIds: [segment.id]));
    }

    return merged;
  }
}
