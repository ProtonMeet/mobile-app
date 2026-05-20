import 'dart:convert';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'user_activity.model.g.dart';

/// Persisted JSON schema; v3
const int kUserActivitySchemaVersion = 3;

/// Minimum "ever created" or "ever completed" threshold for any store-review path.
const int kMinCreatedOrCompletedForStoreReview = 1;

/// How many completed meetings must fall inside the recency window, each clean on
/// feedback (see [kFeedbackDislikeStarsMaxExclusive]), connection, and interruption,
/// to treat the user as satisfied for store review.
const int kStoreReviewRecentCompletionsRequired = 2;

/// Only completions with `endedAt >= now - this` count as "recent" for review gating.
const int kStoreReviewCompletionRecencySeconds = 90 * 24 * 60 * 60; // 90 days

/// Star scores **strictly below** this value count as dislike.
const int kFeedbackDislikeStarsMaxExclusive = 5;

/// After the user taps “not really” on the pre–store-review sheet, do not offer
/// that sheet / deferred review again until this window has passed.
const int kPreRatingNegativeCooldownSeconds = 7 * 24 * 60 * 60; // 7 days

/// Placeholder meaning the user did not submit meeting feedback
/// for that completion yet.
const int kCompletionNoFeedbackScore = -1;

List<int> _intListFromJson(Object? json) {
  if (json is! List) return const [];
  return json
      .map(
        (e) => e is int
            ? e
            : e is num
            ? e.toInt()
            : int.tryParse('$e') ?? 0,
      )
      .toList();
}

List<dynamic> _intListToJson(List<int> list) => list;

/// Persisted engagement used to gate in-app store review (deferred to next launch).
@JsonSerializable()
class UserActivityPersistedV1 {
  const UserActivityPersistedV1({
    int? version,
    this.meetingsCreatedCount = 0,
    this.meetingsCompletedCount = 0,
    this.createdAtEpochSec = const [],
    this.completedAtEpochSec = const [],
    this.completedFeedbackScores = const [],
    this.completedHadBadConnection = const [],
    this.completedWasInterrupted = const [],
    this.feedbackAtEpochSec = const [],
    this.feedbackScores = const [],
    this.hasSubmittedFeedbackBelow5Stars = false,
    this.pendingDeferredStoreReview = false,
    this.lastPreRatingNegativeEpochSec = 0,
  }) : version = version ?? kUserActivitySchemaVersion;

  static const int _listCap = 48;

  @JsonKey(name: 'v', defaultValue: kUserActivitySchemaVersion)
  final int version;

  @JsonKey(name: 'mc', defaultValue: 0)
  final int meetingsCreatedCount;

  @JsonKey(name: 'mco', defaultValue: 0)
  final int meetingsCompletedCount;

  @JsonKey(name: 'ca', fromJson: _intListFromJson, toJson: _intListToJson)
  final List<int> createdAtEpochSec;

  @JsonKey(name: 'co', fromJson: _intListFromJson, toJson: _intListToJson)
  final List<int> completedAtEpochSec;

  /// Parallel to [completedAtEpochSec]: [kCompletionNoFeedbackScore] or 1–5 star score.
  @JsonKey(name: 'cfs', fromJson: _intListFromJson, toJson: _intListToJson)
  final List<int> completedFeedbackScores;

  /// Parallel to [completedAtEpochSec]: `1` if the meeting had transport/reconnect issues.
  @JsonKey(name: 'cbc', fromJson: _intListFromJson, toJson: _intListToJson)
  final List<int> completedHadBadConnection;

  /// Parallel to [completedAtEpochSec]: `1` if the meeting had an app-level rejoin / interrupt flow.
  @JsonKey(name: 'cwi', fromJson: _intListFromJson, toJson: _intListToJson)
  final List<int> completedWasInterrupted;

  @JsonKey(name: 'fa', fromJson: _intListFromJson, toJson: _intListToJson)
  final List<int> feedbackAtEpochSec;

  @JsonKey(name: 'fs', fromJson: _intListFromJson, toJson: _intListToJson)
  final List<int> feedbackScores;

  /// Legacy v1 aggregate; kept for JSON compatibility, cleared on write from v2 paths.
  @JsonKey(name: 'h5', defaultValue: false)
  final bool hasSubmittedFeedbackBelow5Stars;

  @JsonKey(name: 'pd', defaultValue: false)
  final bool pendingDeferredStoreReview;

  /// Last time the user chose the negative path on the pre-rating sheet; used
  /// with [kPreRatingNegativeCooldownSeconds]. `0` means never.
  @JsonKey(name: 'pn', defaultValue: 0)
  final int lastPreRatingNegativeEpochSec;

  factory UserActivityPersistedV1.fromJson(Map<String, dynamic> json) {
    final rawV = json['v'];
    final v = rawV is int
        ? rawV
        : rawV is num
        ? rawV.toInt()
        : int.tryParse('$rawV');
    if (v != 1 && v != 2 && v != 3) return const UserActivityPersistedV1();
    final o = _$UserActivityPersistedV1FromJson(json);
    final normalized = o._normalizeCompletionRows();
    return v != kUserActivitySchemaVersion
        ? normalized._migrateLegacyFeedbackFromV1()
        : normalized;
  }

  /// Decodes the persisted JSON [String] for user-activity state (Hive / preferences).
  factory UserActivityPersistedV1.fromPreferenceJsonString(
    Object? raw, {
    void Function(Object error, StackTrace stackTrace)? onParseFailure,
  }) {
    if (raw is! String || raw.isEmpty) {
      return const UserActivityPersistedV1();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return UserActivityPersistedV1.fromJson(decoded);
      }
    } catch (e, st) {
      onParseFailure?.call(e, st);
    }
    return const UserActivityPersistedV1();
  }

  Map<String, dynamic> toJson() => _$UserActivityPersistedV1ToJson(this);

  String toPreferenceJsonString() => jsonEncode(toJson());

  UserActivityPersistedV1 copyWith({
    int? version,
    int? meetingsCreatedCount,
    int? meetingsCompletedCount,
    List<int>? createdAtEpochSec,
    List<int>? completedAtEpochSec,
    List<int>? completedFeedbackScores,
    List<int>? completedHadBadConnection,
    List<int>? completedWasInterrupted,
    List<int>? feedbackAtEpochSec,
    List<int>? feedbackScores,
    bool? hasSubmittedFeedbackBelow5Stars,
    bool? pendingDeferredStoreReview,
    int? lastPreRatingNegativeEpochSec,
  }) {
    return UserActivityPersistedV1(
      version: version ?? this.version,
      meetingsCreatedCount: meetingsCreatedCount ?? this.meetingsCreatedCount,
      meetingsCompletedCount:
          meetingsCompletedCount ?? this.meetingsCompletedCount,
      createdAtEpochSec: createdAtEpochSec ?? this.createdAtEpochSec,
      completedAtEpochSec: completedAtEpochSec ?? this.completedAtEpochSec,
      completedFeedbackScores:
          completedFeedbackScores ?? this.completedFeedbackScores,
      completedHadBadConnection:
          completedHadBadConnection ?? this.completedHadBadConnection,
      completedWasInterrupted:
          completedWasInterrupted ?? this.completedWasInterrupted,
      feedbackAtEpochSec: feedbackAtEpochSec ?? this.feedbackAtEpochSec,
      feedbackScores: feedbackScores ?? this.feedbackScores,
      hasSubmittedFeedbackBelow5Stars:
          hasSubmittedFeedbackBelow5Stars ??
          this.hasSubmittedFeedbackBelow5Stars,
      pendingDeferredStoreReview:
          pendingDeferredStoreReview ?? this.pendingDeferredStoreReview,
      lastPreRatingNegativeEpochSec:
          lastPreRatingNegativeEpochSec ?? this.lastPreRatingNegativeEpochSec,
    );
  }

  UserActivityPersistedV1 _normalizeCompletionRows() {
    final co = completedAtEpochSec;
    var cfs = [...completedFeedbackScores];
    var cbc = [...completedHadBadConnection];
    var cwi = [...completedWasInterrupted];
    while (cfs.length < co.length) {
      cfs.add(kCompletionNoFeedbackScore);
    }
    while (cbc.length < co.length) {
      cbc.add(0);
    }
    while (cwi.length < co.length) {
      cwi.add(0);
    }
    if (cfs.length > co.length) {
      cfs = cfs.sublist(0, co.length);
    }
    if (cbc.length > co.length) {
      cbc = cbc.sublist(0, co.length);
    }
    if (cwi.length > co.length) {
      cwi = cwi.sublist(0, co.length);
    }
    return copyWith(
      completedFeedbackScores: cfs,
      completedHadBadConnection: cbc,
      completedWasInterrupted: cwi,
      version: kUserActivitySchemaVersion,
    );
  }

  /// v1 was never released publicly: drop legacy `fa` / `fs` / `h5` and reset
  /// per-completion feedback to “no feedback” for each [completedAtEpochSec] row.
  UserActivityPersistedV1 _migrateLegacyFeedbackFromV1() {
    final next = _normalizeCompletionRows();
    final co = next.completedAtEpochSec;
    return next
        .copyWith(
          completedFeedbackScores: List<int>.filled(
            co.length,
            kCompletionNoFeedbackScore,
          ),
          feedbackAtEpochSec: const [],
          feedbackScores: const [],
          hasSubmittedFeedbackBelow5Stars: false,
          version: kUserActivitySchemaVersion,
        )
        ._normalizeCompletionRows();
  }

  UserActivityPersistedV1 _trimLists() {
    List<int> tail(List<int> a) =>
        a.length <= _listCap ? a : a.sublist(a.length - _listCap);

    final normalized = _normalizeCompletionRows();
    final tCa = tail(normalized.createdAtEpochSec);
    final tCo = tail(normalized.completedAtEpochSec);
    final drop = normalized.completedAtEpochSec.length - tCo.length;
    final cfs = [...normalized.completedFeedbackScores];
    final cbc = [...normalized.completedHadBadConnection];
    final cwi = [...normalized.completedWasInterrupted];
    final tCfs = drop > 0 ? cfs.sublist(drop) : cfs;
    final tCbc = drop > 0 ? cbc.sublist(drop) : cbc;
    final tCwi = drop > 0 ? cwi.sublist(drop) : cwi;

    return normalized.copyWith(
      createdAtEpochSec: tCa,
      completedAtEpochSec: tCo,
      completedFeedbackScores: tCfs,
      completedHadBadConnection: tCbc,
      completedWasInterrupted: tCwi,
      feedbackAtEpochSec: tail(normalized.feedbackAtEpochSec),
      feedbackScores: tail(normalized.feedbackScores),
    );
  }

  UserActivityPersistedV1 withMeetingCreated(int epochSec) {
    final next = copyWith(
      meetingsCreatedCount: meetingsCreatedCount + 1,
      createdAtEpochSec: [...createdAtEpochSec, epochSec],
    );
    return next._trimLists();
  }

  UserActivityPersistedV1 withMeetingCompleted(
    int epochSec, {
    bool hadBadConnection = false,
    bool wasInterrupted = false,
  }) {
    final normalized = _normalizeCompletionRows();
    final bad = hadBadConnection ? 1 : 0;
    final intr = wasInterrupted ? 1 : 0;
    final next = normalized.copyWith(
      meetingsCompletedCount: normalized.meetingsCompletedCount + 1,
      completedAtEpochSec: [...normalized.completedAtEpochSec, epochSec],
      completedFeedbackScores: [
        ...normalized.completedFeedbackScores,
        kCompletionNoFeedbackScore,
      ],
      completedHadBadConnection: [...normalized.completedHadBadConnection, bad],
      completedWasInterrupted: [...normalized.completedWasInterrupted, intr],
      pendingDeferredStoreReview: true,
    );
    return next._trimLists();
  }

  /// Records a star [score] for the most recent completion at or before
  /// [epochSec]. Prefers the latest still-unrated row; otherwise overwrites the
  /// latest matching row. If no completion row exists yet (e.g. feedback
  /// arrived before [withMeetingCompleted]), synthesises a completion at
  /// [epochSec] so the score is never silently dropped.
  UserActivityPersistedV1 withFeedback({
    required int epochSec,
    required int score,
  }) {
    final normalized = _normalizeCompletionRows();
    var co = [...normalized.completedAtEpochSec];
    var cfs = [...normalized.completedFeedbackScores];
    var cbc = [...normalized.completedHadBadConnection];
    var cwi = [...normalized.completedWasInterrupted];

    var assignIdx = -1;
    for (var i = co.length - 1; i >= 0; i--) {
      if (co[i] <= epochSec && cfs[i] == kCompletionNoFeedbackScore) {
        assignIdx = i;
        break;
      }
    }
    if (assignIdx < 0) {
      for (var i = co.length - 1; i >= 0; i--) {
        if (co[i] <= epochSec) {
          assignIdx = i;
          break;
        }
      }
    }
    if (assignIdx >= 0) {
      cfs[assignIdx] = score;
    } else {
      // No completion row matches: append a synthetic one so the score is
      // attributed and counted by the recency window.
      co = [...co, epochSec];
      cfs = [...cfs, score];
      cbc = [...cbc, 0];
      cwi = [...cwi, 0];
    }

    final below5 = score < kFeedbackDislikeStarsMaxExclusive;
    final next = normalized.copyWith(
      // v3 source of truth is per-completion `cfs`; do not append to legacy
      // `fa`/`fs` (those duplicate the score and bloat the persisted JSON).
      feedbackAtEpochSec: const [],
      feedbackScores: const [],
      completedAtEpochSec: co,
      completedFeedbackScores: cfs,
      completedHadBadConnection: cbc,
      completedWasInterrupted: cwi,
      hasSubmittedFeedbackBelow5Stars:
          normalized.hasSubmittedFeedbackBelow5Stars || below5,
    );
    return next._trimLists();
  }

  /// Indices of completions in [completedAtEpochSec] that fall inside the recency window.
  List<int> completionIndicesInRecencyWindow({required int nowEpochSec}) {
    final normalized = _normalizeCompletionRows();
    final cutoff = nowEpochSec - kStoreReviewCompletionRecencySeconds;
    final out = <int>[];
    for (var i = 0; i < normalized.completedAtEpochSec.length; i++) {
      if (normalized.completedAtEpochSec[i] >= cutoff) {
        out.add(i);
      }
    }
    return out;
  }

  /// True when the user has baseline activity **and** the last
  /// [kStoreReviewRecentCompletionsRequired] completions that fall inside the recency
  /// window each have: no recorded dislike (star score **strictly below**
  /// [kFeedbackDislikeStarsMaxExclusive]), no bad-connection flag, and no interrupted
  /// meeting flag.
  ///
  /// Older completions inside the window are ignored. Missing feedback
  /// ([kCompletionNoFeedbackScore]) is allowed.
  bool meetsStoreReviewEngagementRules({int? nowEpochSec}) {
    final now = nowEpochSec ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final branchEngagement =
        meetingsCreatedCount >= kMinCreatedOrCompletedForStoreReview ||
        meetingsCompletedCount >= kMinCreatedOrCompletedForStoreReview;
    if (!branchEngagement) return false;

    final normalized = _normalizeCompletionRows();
    final recent = normalized.completionIndicesInRecencyWindow(
      nowEpochSec: now,
    );
    if (recent.length < kStoreReviewRecentCompletionsRequired) return false;

    for (final i in recent) {
      final s = i < normalized.completedFeedbackScores.length
          ? normalized.completedFeedbackScores[i]
          : kCompletionNoFeedbackScore;
      if (s != kCompletionNoFeedbackScore &&
          s < kFeedbackDislikeStarsMaxExclusive) {
        return false;
      }
    }

    final start = recent.length - kStoreReviewRecentCompletionsRequired;
    for (var j = start; j < recent.length; j++) {
      final i = recent[j];
      final bad = i < normalized.completedHadBadConnection.length
          ? normalized.completedHadBadConnection[i]
          : 0;
      final intr = i < normalized.completedWasInterrupted.length
          ? normalized.completedWasInterrupted[i]
          : 0;
      if (bad != 0 || intr != 0) {
        return false;
      }
    }
    return true;
  }

  /// True while [kPreRatingNegativeCooldownSeconds] has not elapsed since the
  /// user last dismissed the pre-rating flow via the negative action.
  bool isPreRatingNegativeCooldownActive({int? nowEpochSec}) {
    final last = lastPreRatingNegativeEpochSec;
    if (last <= 0) return false;
    final now = nowEpochSec ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now - last < kPreRatingNegativeCooldownSeconds;
  }
}
