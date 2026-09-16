/// Timing, retry, display tuning, and LiveKit participant attributes for live
/// captions.
///
/// Mirrors the web client (`constants.ts`, `useCaptionsAgentLifecycle.ts`,
/// `useMlsSession.ts`, `useTranscriptions.ts`, `useCaptionsPreference.ts`).
/// Import this file anywhere captions agent lifecycle or transcription UI
/// logic needs shared values.
abstract final class LiveCaptionsConstants {
  // ---------------------------------------------------------------------------
  // Captions agent lifecycle (enable / disable / retry)
  // ---------------------------------------------------------------------------

  /// Upper bound for the enable flow: waiting for the STT agent to join,
  /// admit, and become ready. When this elapses without success, captions are
  /// turned off automatically (same window used for enable retries).
  static const Duration agentWait = Duration(seconds: 30);

  /// Delay between enable/admit retry attempts while still inside [agentWait].
  static const Duration agentRetryBackoff = Duration(seconds: 3);

  /// After the last client stops wanting captions, wait this long before
  /// requesting agent removal (avoids flapping when users toggle quickly).
  static const Duration agentDisableGrace = Duration(seconds: 10);

  /// Per-attempt delay schedule for enable/admit retries within [agentWait].
  /// First attempt is immediate; subsequent attempts use [agentRetryBackoff]
  /// until the 30-second window is exhausted (11 attempts total).
  static const List<Duration> agentRetryDelays = [
    Duration.zero,
    agentRetryBackoff,
    agentRetryBackoff,
    agentRetryBackoff,
    agentRetryBackoff,
    agentRetryBackoff,
    agentRetryBackoff,
    agentRetryBackoff,
    agentRetryBackoff,
    agentRetryBackoff,
    agentRetryBackoff,
  ];

  /// How long to wait for server/agent confirmation after a disable request
  /// before treating teardown as timed out.
  static const Duration teardownTimeout = Duration(seconds: 15);

  /// Maximum disable/teardown attempts when removal is not confirmed in time.
  static const int teardownMaxAttempts = 3;

  // ---------------------------------------------------------------------------
  // Transcription stream & on-screen display
  // ---------------------------------------------------------------------------

  /// Agent is present in the room but no decodable caption segments arrive
  /// within this window → treat captions as failed/stuck and surface error UX.
  static const Duration readyTimeout = Duration(seconds: 20);

  /// How long a final caption segment stays visible before fading out.
  static const Duration finalLinger = Duration(seconds: 4);

  /// Interim (non-final) segments older than this are dropped as stale.
  static const Duration staleSegment = Duration(seconds: 15);

  /// Merge consecutive segments from the same speaker when the gap between
  /// them is at most this duration.
  static const Duration mergeGap = Duration(milliseconds: 1500);

  /// Maximum character length of a single merged caption line before splitting.
  static const int maxMergedLength = 180;

  /// Maximum number of merged caption lines kept in the captions sheet.
  /// Lines still on this list are pinned against [finalLinger] / [staleSegment]
  /// expiry so the user can scroll back through recent speech.
  static const int maxTranscriptLines = 50;

  // ---------------------------------------------------------------------------
  // LiveKit participant attributes (Meet-defined, not LiveKit built-ins)
  // ---------------------------------------------------------------------------

  /// Participant attribute key: whether this client wants live captions.
  /// Web: `WANTS_CAPTIONS_ATTR` in `constants.ts` / `useCaptionsPreference.ts`.
  static const String wantsCaptionsAttr = 'wants_captions';

  /// Participant attribute key: STT language selection for this client.
  /// Web: `CAPTION_LANGUAGE_ATTR` in `constants.ts` / `useCaptionsPreference.ts`.
  static const String captionLanguageAttr = 'caption_language';

  /// Fallback language label when [captionLanguageAttr] is absent or cleared.
  /// STT auto-detect (multi-language) mode.
  static const String defaultCaptionLanguage = 'multi';

  /// [wantsCaptionsAttr] value while captions are enabled for this participant.
  static const String wantsCaptionsEnabled = 'true';

  /// [wantsCaptionsAttr] value written when turning captions off. LiveKit treats
  /// an empty string as "remove this attribute key" (same as web `''`).
  static const String wantsCaptionsDisabled = '';

  /// [captionLanguageAttr] value for UI "Auto-detect". Empty/removal → STT
  /// auto-detect (multi). Use [wantsCaptionsDisabled] semantics when writing.
  static const String captionLanguageAutoDetect = '';

  /// Normalizes a read [captionLanguageAttr] value for UI display.
  ///
  /// Web equivalent: `displayLanguage = attributeValue || 'multi'`.
  /// Missing, null, or blank → [defaultCaptionLanguage].
  static String displayCaptionLanguage(String? attributeValue) {
    final trimmed = attributeValue?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return defaultCaptionLanguage;
    }
    return trimmed;
  }

  /// Parses [wantsCaptionsAttr] from LiveKit (strict — not truthy coercion).
  ///
  /// Web equivalent: `value === 'true'`.
  static bool parseWantsCaptions(String? attributeValue) =>
      attributeValue == wantsCaptionsEnabled;

  /// Maps a UI/API language code to the LiveKit attribute write value.
  ///
  /// Auto-detect ([defaultCaptionLanguage]) → `''` (LiveKit removes the key).
  /// Do not write `'multi'` to LiveKit.
  static String captionLanguageToAttributeValue(String language) {
    final trimmed = language.trim();
    if (trimmed.isEmpty || trimmed == defaultCaptionLanguage) {
      return captionLanguageAutoDetect;
    }
    return trimmed;
  }

  /// Maps a UI toggle to the LiveKit [wantsCaptionsAttr] write value.
  static String wantsCaptionsToAttributeValue({required bool enabled}) =>
      enabled ? wantsCaptionsEnabled : wantsCaptionsDisabled;

  // ---------------------------------------------------------------------------
  // LiveKit text stream (lk.transcription wire format)
  // ---------------------------------------------------------------------------

  /// Text stream topic for MLS-encrypted caption chunks from SttAgent.
  static const String transcriptionTopic = 'lk.transcription';

  /// Stream attribute: stable segment id (`lk.segment_id`).
  static const String segmentIdAttr = 'lk.segment_id';

  /// Stream attribute: final vs interim transcript (`lk.transcription_final`).
  static const String transcriptionFinalAttr = 'lk.transcription_final';

  /// Stream attribute: speaker audio track SID (`lk.transcribed_track_id`).
  static const String transcribedTrackIdAttr = 'lk.transcribed_track_id';

  /// Stream attribute value when a transcript segment is final.
  static const String transcriptionFinalEnabled = 'true';

  /// LiveKit participant identity prefix for the STT agent worker.
  static const String sttAgentPrefix = 'SttAgent#';

  /// Parses [transcriptionFinalAttr] (strict `=== 'true'`, same as web).
  static bool parseTranscriptionFinal(String? attributeValue) =>
      attributeValue == transcriptionFinalEnabled;
}
