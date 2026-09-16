import 'package:livekit_client/livekit_client.dart';
import 'package:meet/constants/live_captions_constants.dart';
import 'package:meet/models/live_captions/live_caption_agent.dart';

/// Read helpers for Meet live-caption keys on any [Participant].
extension LiveCaptionParticipantRead on Participant {
  /// Raw [LiveCaptionsConstants.wantsCaptionsAttr] value (`''` if absent).
  String get rawWantsCaptionsAttribute =>
      attributes[LiveCaptionsConstants.wantsCaptionsAttr] ?? '';

  /// Whether this participant wants live captions (`wants_captions === 'true'`).
  ///
  /// Only the literal `'true'` counts as enabled; missing/empty/other → off.
  bool get wantsCaptions =>
      LiveCaptionsConstants.parseWantsCaptions(rawWantsCaptionsAttribute);

  /// Raw [LiveCaptionsConstants.captionLanguageAttr] value (`''` if absent).
  String get rawCaptionLanguageAttribute =>
      attributes[LiveCaptionsConstants.captionLanguageAttr] ?? '';

  /// STT language for UI (`value || 'multi'` normalization).
  String get captionLanguage =>
      LiveCaptionsConstants.displayCaptionLanguage(rawCaptionLanguageAttribute);

  /// Meet STT caption agent (`SttAgent#…`). Excluded from wanters count.
  bool get isLiveCaptionsAgent => isCaptionAgent(this);

  /// Human participant with captions enabled; used for room wanters tally.
  bool get countsAsLiveCaptionsWanter => !isLiveCaptionsAgent && wantsCaptions;
}

/// Write helpers for the local participant's caption preference attributes.
extension LiveCaptionLocalParticipantWrite on LocalParticipant {
  /// Sets [LiveCaptionsConstants.wantsCaptionsAttr].
  ///
  /// Enable → `'true'`; disable → `''` (LiveKit removes the key).
  Future<void> setLiveCaptionsWanted({required bool enabled}) => setAttributes({
    LiveCaptionsConstants.wantsCaptionsAttr:
        LiveCaptionsConstants.wantsCaptionsToAttributeValue(enabled: enabled),
  });

  /// Sets [LiveCaptionsConstants.captionLanguageAttr].
  ///
  /// [language] is a UI code (e.g. `'zh-TW'`) or [LiveCaptionsConstants.defaultCaptionLanguage]
  /// for auto-detect. Auto-detect writes `''` — never `'multi'`.
  Future<void> setLiveCaptionLanguage(String language) => setAttributes({
    LiveCaptionsConstants.captionLanguageAttr:
        LiveCaptionsConstants.captionLanguageToAttributeValue(language),
  });
}

/// Room-level observers for caption demand (wanters) and participant iteration.
extension LiveCaptionRoomWanters on Room {
  /// All connected participants (local + remote).
  Iterable<Participant> get allParticipants sync* {
    final local = localParticipant;
    if (local != null) {
      yield local;
    }
    yield* remoteParticipants.values;
  }

  /// Humans with `wants_captions === 'true'` (agents excluded).
  ///
  /// Web equivalent: `useCaptionsWantersCount`.
  int get liveCaptionsWantersCount => allParticipants
      .where((participant) => participant.countsAsLiveCaptionsWanter)
      .length;

  /// Whether any human currently wants captions in this room.
  bool get hasLiveCaptionsWanters => liveCaptionsWantersCount > 0;

  /// Participants that currently count as caption wanters.
  Iterable<Participant> get liveCaptionsWanterParticipants => allParticipants
      .where((participant) => participant.countsAsLiveCaptionsWanter);
}

/// When to recompute wanters / react to caption preference changes.
///
/// Web: `PARTICIPANT_SET_EVENTS` + `ParticipantAttributesChanged`
/// in `useCaptionsWantersCount.ts`.
bool liveCaptionShouldRecomputeWanters(Object? event) =>
    event is ParticipantConnectedEvent ||
    event is ParticipantDisconnectedEvent ||
    event is RoomConnectedEvent ||
    event is RoomReconnectedEvent ||
    event is ParticipantAttributesChanged;

/// Whether [event] is a caption participant-attribute change for [participant].
bool liveCaptionParticipantAttributesChanged(
  Object? event,
  Participant participant,
) {
  if (event is! ParticipantAttributesChanged) {
    return false;
  }
  return event.participant.sid == participant.sid;
}

/// Whether [diff] touches Meet live-caption attribute keys.
bool liveCaptionAttributesDiffIsRelevant(Map<String, String> diff) =>
    diff.containsKey(LiveCaptionsConstants.wantsCaptionsAttr) ||
    diff.containsKey(LiveCaptionsConstants.captionLanguageAttr);
