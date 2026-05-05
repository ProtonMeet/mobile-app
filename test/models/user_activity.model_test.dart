import 'dart:convert';

import 'package:meet/models/user_activity.model.dart';
import 'package:test/test.dart';

import '../helper.dart';

void main() {
  const secPerDay = 24 * 60 * 60;
  final now = 1_700_000_000;
  final inWindow1 = now - 10 * secPerDay;
  final inWindow2 = now - 5 * secPerDay;
  final outWindow = now - kStoreReviewCompletionRecencySeconds - secPerDay;

  testUnit('fromJson returns defaults when schema v is not 1, 2, or 3', () {
    final o = UserActivityPersistedV1.fromJson({'v': 0, 'mc': 99, 'mco': 88});
    expect(o.meetingsCreatedCount, 0);
    expect(o.meetingsCompletedCount, 0);
    expect(o.version, kUserActivitySchemaVersion);
  });

  testUnit(
    'fromJson v2 migrates to v3 and resets per-completion feedback (cfs)',
    () {
      final o = UserActivityPersistedV1.fromJson({
        'v': 2,
        'mc': 2,
        'mco': 3,
        'ca': [10, 20],
        'co': [30, 31],
        'cfs': [-1, 5],
        'fa': [40],
        'fs': [5],
        'h5': true,
        'pd': true,
      });
      expect(o.version, kUserActivitySchemaVersion);
      expect(o.meetingsCreatedCount, 2);
      expect(o.meetingsCompletedCount, 3);
      expect(o.createdAtEpochSec, [10, 20]);
      expect(o.completedAtEpochSec, [30, 31]);
      expect(o.completedFeedbackScores, [-1, -1]);
      expect(o.feedbackAtEpochSec, isEmpty);
      expect(o.feedbackScores, isEmpty);
      expect(o.hasSubmittedFeedbackBelow5Stars, false);
      expect(o.pendingDeferredStoreReview, true);
      expect(o.completedHadBadConnection, [0, 0]);
      expect(o.completedWasInterrupted, [0, 0]);
    },
  );

  testUnit(
    'fromJson v3 preserves cfs, cbc, cwi, fa, fs, and flags without migration',
    () {
      final o = UserActivityPersistedV1.fromJson({
        'v': 3,
        'mc': 1,
        'mco': 2,
        'ca': [1],
        'co': [10, 11],
        'cfs': [5, -1],
        'cbc': [0, 1],
        'cwi': [1, 0],
        'fa': [12],
        'fs': [4],
        'h5': true,
        'pd': false,
      });
      expect(o.version, 3);
      expect(o.completedFeedbackScores, [5, -1]);
      expect(o.completedHadBadConnection, [0, 1]);
      expect(o.completedWasInterrupted, [1, 0]);
      expect(o.feedbackAtEpochSec, [12]);
      expect(o.feedbackScores, [4]);
      expect(o.hasSubmittedFeedbackBelow5Stars, true);
    },
  );

  testUnit(
    'fromJson v1 clears unreleased legacy feedback and resets cfs slots',
    () {
      final o = UserActivityPersistedV1.fromJson({
        'v': 1,
        'mc': 2,
        'mco': 3,
        'ca': [10, 20],
        'co': [30],
        'fa': [40],
        'fs': [5],
        'h5': true,
        'pd': true,
      });
      expect(o.version, kUserActivitySchemaVersion);
      expect(o.completedAtEpochSec, [30]);
      expect(o.completedFeedbackScores, [kCompletionNoFeedbackScore]);
      expect(o.feedbackAtEpochSec, isEmpty);
      expect(o.feedbackScores, isEmpty);
      expect(o.hasSubmittedFeedbackBelow5Stars, false);
    },
  );

  testUnit('fromJson coerces list elements to int', () {
    final o = UserActivityPersistedV1.fromJson({
      'v': 3,
      'ca': [1, 2.0, '3'],
      'co': [],
      'cfs': [],
      'cbc': [],
      'cwi': [],
      'fa': [],
      'fs': [],
    });
    expect(o.createdAtEpochSec, [1, 2, 3]);
  });

  testUnit('fromJson returns defaults when v is null', () {
    final o = UserActivityPersistedV1.fromJson({'v': null, 'mc': 9});
    expect(o.meetingsCreatedCount, 0);
  });

  testUnit('fromJson accepts v as num 2.0', () {
    final o = UserActivityPersistedV1.fromJson({'v': 2.0, 'mc': 1});
    expect(o.meetingsCreatedCount, 1);
    expect(o.version, kUserActivitySchemaVersion);
  });

  testUnit('fromJson accepts v as int 1 in minimal map', () {
    final o = UserActivityPersistedV1.fromJson({'v': 1});
    expect(o.version, kUserActivitySchemaVersion);
    expect(o.meetingsCreatedCount, 0);
    expect(o.createdAtEpochSec, isEmpty);
    expect(o.pendingDeferredStoreReview, false);
  });

  testUnit('fromJson treats non-list list fields as empty', () {
    final o = UserActivityPersistedV1.fromJson({
      'v': 3,
      'ca': 'not-a-list',
      'co': 42,
      'cfs': null,
      'cbc': 'x',
      'cwi': null,
      'fa': {},
      'fs': null,
    });
    expect(o.createdAtEpochSec, isEmpty);
    expect(o.completedAtEpochSec, isEmpty);
    expect(o.completedFeedbackScores, isEmpty);
    expect(o.completedHadBadConnection, isEmpty);
    expect(o.completedWasInterrupted, isEmpty);
    expect(o.feedbackAtEpochSec, isEmpty);
    expect(o.feedbackScores, isEmpty);
  });

  testUnit('toJson uses short storage keys including cfs, cbc, cwi', () {
    const s = UserActivityPersistedV1(
      meetingsCreatedCount: 3,
      meetingsCompletedCount: 2,
      completedAtEpochSec: [1],
      completedFeedbackScores: [-1],
      completedHadBadConnection: [1],
      completedWasInterrupted: [0],
      pendingDeferredStoreReview: true,
    );
    final m = s.toJson();
    expect(
      m.keys,
      containsAll([
        'v',
        'mc',
        'mco',
        'ca',
        'co',
        'cfs',
        'cbc',
        'cwi',
        'fa',
        'fs',
        'h5',
        'pd',
      ]),
    );
    expect(m['v'], kUserActivitySchemaVersion);
    expect(m['mc'], 3);
    expect(m['mco'], 2);
    expect(m['cfs'], [-1]);
    expect(m['cbc'], [1]);
    expect(m['cwi'], [0]);
    expect(m['pd'], true);
  });

  testUnit('toJson / fromJson round-trip preserves fields', () {
    const original = UserActivityPersistedV1(
      meetingsCreatedCount: 1,
      createdAtEpochSec: [100],
      completedAtEpochSec: [200],
      completedFeedbackScores: [4],
      completedHadBadConnection: [0],
      completedWasInterrupted: [1],
      pendingDeferredStoreReview: true,
    );
    final json = original.toJson();
    final restored = UserActivityPersistedV1.fromJson(json);
    expect(restored.meetingsCreatedCount, original.meetingsCreatedCount);
    expect(
      restored.pendingDeferredStoreReview,
      original.pendingDeferredStoreReview,
    );
    expect(restored.createdAtEpochSec, original.createdAtEpochSec);
    expect(restored.completedAtEpochSec, original.completedAtEpochSec);
    expect(restored.completedFeedbackScores, original.completedFeedbackScores);
    expect(
      restored.completedHadBadConnection,
      original.completedHadBadConnection,
    );
    expect(restored.completedWasInterrupted, original.completedWasInterrupted);
  });

  testUnit(
    'toPreferenceJsonString round-trips with fromPreferenceJsonString',
    () {
      const original = UserActivityPersistedV1(
        meetingsCreatedCount: 7,
        pendingDeferredStoreReview: true,
      );
      final restored = UserActivityPersistedV1.fromPreferenceJsonString(
        original.toPreferenceJsonString(),
      );
      expect(restored.meetingsCreatedCount, 7);
      expect(restored.pendingDeferredStoreReview, true);
    },
  );

  testUnit('fromPreferenceJsonString handles null and non-string', () {
    expect(
      UserActivityPersistedV1.fromPreferenceJsonString(
        null,
      ).meetingsCreatedCount,
      0,
    );
    expect(
      UserActivityPersistedV1.fromPreferenceJsonString(42).meetingsCreatedCount,
      0,
    );
    expect(
      UserActivityPersistedV1.fromPreferenceJsonString('').meetingsCreatedCount,
      0,
    );
  });

  testUnit('fromPreferenceJsonString parses valid JSON string', () {
    final raw = jsonEncode({
      'v': 3,
      'mc': 5,
      'mco': 0,
      'ca': [],
      'co': [],
      'cfs': [],
      'cbc': [],
      'cwi': [],
      'fa': [],
      'fs': [],
      'h5': false,
      'pd': false,
    });
    final o = UserActivityPersistedV1.fromPreferenceJsonString(raw);
    expect(o.meetingsCreatedCount, 5);
  });

  testUnit('fromPreferenceJsonString non-map JSON returns defaults', () {
    final o = UserActivityPersistedV1.fromPreferenceJsonString('[1,2,3]');
    expect(o.meetingsCreatedCount, 0);
  });

  testUnit(
    'fromPreferenceJsonString map with invalid schema version yields defaults',
    () {
      final raw = jsonEncode({'v': 0, 'mc': 100});
      final o = UserActivityPersistedV1.fromPreferenceJsonString(raw);
      expect(o.meetingsCreatedCount, 0);
    },
  );

  testUnit('fromPreferenceJsonString invalid JSON invokes onParseFailure', () {
    Object? captured;
    final o = UserActivityPersistedV1.fromPreferenceJsonString(
      '{not json',
      onParseFailure: (e, _) {
        captured = e;
      },
    );
    expect(o.meetingsCreatedCount, 0);
    expect(captured, isNotNull);
  });

  testUnit(
    'fromPreferenceJsonString does not call onParseFailure for empty',
    () {
      var called = false;
      UserActivityPersistedV1.fromPreferenceJsonString(
        '',
        onParseFailure: (_, _) => called = true,
      );
      expect(called, false);
    },
  );

  testUnit('copyWith overrides selected fields', () {
    const s = UserActivityPersistedV1(meetingsCreatedCount: 1);
    final next = s.copyWith(
      meetingsCompletedCount: 2,
      pendingDeferredStoreReview: true,
    );
    expect(next.meetingsCreatedCount, 1);
    expect(next.meetingsCompletedCount, 2);
    expect(next.pendingDeferredStoreReview, true);
  });

  testUnit('meetsStoreReviewEngagementRules: false with no completions', () {
    const s = UserActivityPersistedV1(meetingsCreatedCount: 1);
    expect(s.meetsStoreReviewEngagementRules(nowEpochSec: now), false);
  });

  testUnit(
    'meetsStoreReviewEngagementRules: false when fewer than 2 in window',
    () {
      final s = UserActivityPersistedV1(
        meetingsCreatedCount: 1,
        meetingsCompletedCount: 1,
        completedAtEpochSec: [inWindow1],
        completedFeedbackScores: [kCompletionNoFeedbackScore],
      );
      expect(s.meetsStoreReviewEngagementRules(nowEpochSec: now), false);
    },
  );

  testUnit(
    'meetsStoreReviewEngagementRules: true with 2 in window and no dislike',
    () {
      final s = UserActivityPersistedV1(
        meetingsCreatedCount: 1,
        meetingsCompletedCount: 2,
        completedAtEpochSec: [inWindow1, inWindow2],
        completedFeedbackScores: [kCompletionNoFeedbackScore, 5],
      );
      expect(s.meetsStoreReviewEngagementRules(nowEpochSec: now), true);
    },
  );

  testUnit(
    'meetsStoreReviewEngagementRules: false when last in-window score is dislike (<5)',
    () {
      final s = UserActivityPersistedV1(
        meetingsCreatedCount: 1,
        meetingsCompletedCount: 3,
        completedAtEpochSec: [inWindow1, inWindow2, now - secPerDay],
        completedFeedbackScores: [5, 5, 3],
      );
      expect(s.meetsStoreReviewEngagementRules(nowEpochSec: now), false);
    },
  );

  testUnit(
    'meetsStoreReviewEngagementRules: 4 stars counts as dislike and blocks',
    () {
      final s = UserActivityPersistedV1(
        meetingsCreatedCount: 1,
        meetingsCompletedCount: 3,
        completedAtEpochSec: [inWindow1, inWindow2, now - secPerDay],
        completedFeedbackScores: [5, 5, 4],
      );
      expect(s.meetsStoreReviewEngagementRules(nowEpochSec: now), false);
    },
  );

  testUnit(
    'meetsStoreReviewEngagementRules: older dislike in same window also blocks',
    () {
      final s = UserActivityPersistedV1(
        meetingsCreatedCount: 1,
        meetingsCompletedCount: 3,
        completedAtEpochSec: [inWindow1, inWindow2, now - secPerDay],
        completedFeedbackScores: [2, 5, 5],
      );
      expect(s.meetsStoreReviewEngagementRules(nowEpochSec: now), false);
    },
  );

  testUnit(
    'meetsStoreReviewEngagementRules: false when no create or complete',
    () {
      expect(
        const UserActivityPersistedV1().meetsStoreReviewEngagementRules(
          nowEpochSec: now,
        ),
        false,
      );
    },
  );

  testUnit(
    'meetsStoreReviewEngagementRules: out-of-window completions do not count',
    () {
      final s = UserActivityPersistedV1(
        meetingsCreatedCount: 1,
        meetingsCompletedCount: 2,
        completedAtEpochSec: [outWindow, inWindow1],
        completedFeedbackScores: [2, 5],
      );
      expect(s.meetsStoreReviewEngagementRules(nowEpochSec: now), false);
    },
  );

  testUnit(
    'meetsStoreReviewEngagementRules: h5 legacy does not block when recent ok',
    () {
      final s = UserActivityPersistedV1(
        meetingsCreatedCount: 1,
        meetingsCompletedCount: 2,
        hasSubmittedFeedbackBelow5Stars: true,
        completedAtEpochSec: [inWindow1, inWindow2],
        completedFeedbackScores: [5, 5],
      );
      expect(s.meetsStoreReviewEngagementRules(nowEpochSec: now), true);
    },
  );

  testUnit(
    'meetsStoreReviewEngagementRules: false when recent completion had bad connection',
    () {
      final s = UserActivityPersistedV1(
        meetingsCreatedCount: 1,
        meetingsCompletedCount: 2,
        completedAtEpochSec: [inWindow1, inWindow2],
        completedFeedbackScores: [5, 5],
        completedHadBadConnection: [0, 1],
      );
      expect(s.meetsStoreReviewEngagementRules(nowEpochSec: now), false);
    },
  );

  testUnit(
    'meetsStoreReviewEngagementRules: false when recent completion was interrupted',
    () {
      final s = UserActivityPersistedV1(
        meetingsCreatedCount: 1,
        meetingsCompletedCount: 2,
        completedAtEpochSec: [inWindow1, inWindow2],
        completedFeedbackScores: [5, 5],
        completedWasInterrupted: [0, 1],
      );
      expect(s.meetsStoreReviewEngagementRules(nowEpochSec: now), false);
    },
  );

  testUnit(
    'completionIndicesInRecencyWindow lists indices in chronological order',
    () {
      final s = UserActivityPersistedV1(
        completedAtEpochSec: [outWindow, inWindow1, inWindow2],
      );
      expect(s.completionIndicesInRecencyWindow(nowEpochSec: now), [1, 2]);
    },
  );

  testUnit('withMeetingCreated increments and appends timestamp', () {
    const s = UserActivityPersistedV1();
    final next = s.withMeetingCreated(123);
    expect(next.meetingsCreatedCount, 1);
    expect(next.createdAtEpochSec, [123]);
  });

  testUnit(
    'withMeetingCompleted sets pending, cfs, cbc, cwi, and increments',
    () {
      const s = UserActivityPersistedV1();
      final next = s.withMeetingCompleted(
        999,
        hadBadConnection: true,
        wasInterrupted: true,
      );
      expect(next.meetingsCompletedCount, 1);
      expect(next.pendingDeferredStoreReview, true);
      expect(next.completedAtEpochSec, [999]);
      expect(next.completedFeedbackScores, [kCompletionNoFeedbackScore]);
      expect(next.completedHadBadConnection, [1]);
      expect(next.completedWasInterrupted, [1]);
    },
  );

  testUnit(
    'withFeedback with no completion synthesises a completion row',
    () {
      const s = UserActivityPersistedV1();
      final next = s.withFeedback(epochSec: 100, score: 4);
      expect(next.hasSubmittedFeedbackBelow5Stars, true);
      expect(next.completedAtEpochSec, [100]);
      expect(next.completedFeedbackScores, [4]);
      expect(next.completedHadBadConnection, [0]);
      expect(next.completedWasInterrupted, [0]);
      expect(next.feedbackScores, isEmpty);
      expect(next.feedbackAtEpochSec, isEmpty);
    },
  );

  testUnit('withFeedback score 5 does not set below-5 flag', () {
    const s = UserActivityPersistedV1();
    final next = s.withFeedback(epochSec: 1, score: 5);
    expect(next.hasSubmittedFeedbackBelow5Stars, false);
    expect(next.completedFeedbackScores, [5]);
    expect(next.feedbackScores, isEmpty);
  });

  testUnit('withFeedback assigns to cfs for matching completion', () {
    UserActivityPersistedV1 s = const UserActivityPersistedV1();
    s = s.withMeetingCompleted(10);
    s = s.withFeedback(epochSec: 20, score: 4);
    expect(s.completedFeedbackScores, [4]);
    expect(s.completedAtEpochSec, [10]);
  });

  testUnit(
    'each completed-then-rated meeting persists into its own cfs slot',
    () {
      UserActivityPersistedV1 s = const UserActivityPersistedV1();
      s = s.withMeetingCompleted(10);
      s = s.withFeedback(epochSec: 11, score: 5);
      s = s.withMeetingCompleted(20);
      s = s.withFeedback(epochSec: 21, score: 4);
      s = s.withMeetingCompleted(30);
      s = s.withFeedback(epochSec: 31, score: 3);
      expect(s.completedAtEpochSec, [10, 20, 30]);
      expect(s.completedFeedbackScores, [5, 4, 3]);
    },
  );

  testUnit(
    'withFeedback without a fresh completion row overwrites the latest slot',
    () {
      // When feedback arrives without a matching unrated completion, the
      // latest in-range row is overwritten (no synthetic rows are appended
      // for repeat calls in this case).
      UserActivityPersistedV1 s = const UserActivityPersistedV1();
      s = s.withFeedback(epochSec: 1, score: 5);
      s = s.withFeedback(epochSec: 2, score: 3);
      expect(s.completedAtEpochSec, [1]);
      expect(s.completedFeedbackScores, [3]);
      expect(s.feedbackScores, isEmpty);
      expect(s.hasSubmittedFeedbackBelow5Stars, true);
    },
  );

  testUnit('withFeedback does not grow legacy fa/fs lists', () {
    UserActivityPersistedV1 s = const UserActivityPersistedV1();
    for (var i = 0; i < 50; i++) {
      s = s.withFeedback(epochSec: i, score: 5);
    }
    expect(s.feedbackAtEpochSec, isEmpty);
    expect(s.feedbackScores, isEmpty);
    // Without interleaved completions, repeat withFeedback overwrites the
    // single synthetic row; only one slot is kept.
    expect(s.completedFeedbackScores, [5]);
    expect(s.completedAtEpochSec, [0]);
  });

  testUnit('withMeetingCreated does not set pendingDeferredStoreReview', () {
    const s = UserActivityPersistedV1();
    final next = s.withMeetingCreated(1);
    expect(next.pendingDeferredStoreReview, false);
  });

  testUnit('withMeetingCompleted trims completed and cfs to cap', () {
    UserActivityPersistedV1 s = const UserActivityPersistedV1();
    for (var i = 0; i < 50; i++) {
      s = s.withMeetingCompleted(i);
    }
    expect(s.completedAtEpochSec.length, 48);
    expect(s.completedFeedbackScores.length, 48);
    expect(s.completedHadBadConnection.length, 48);
    expect(s.completedWasInterrupted.length, 48);
    expect(s.completedAtEpochSec.first, 2);
    expect(s.completedAtEpochSec.last, 49);
    expect(s.pendingDeferredStoreReview, true);
  });

  testUnit('withMeetingCreated trims lists when all are long', () {
    UserActivityPersistedV1 s = UserActivityPersistedV1(
      createdAtEpochSec: List.generate(50, (i) => i),
      completedAtEpochSec: List.generate(50, (i) => i + 1000),
      completedFeedbackScores: List.generate(
        50,
        (_) => kCompletionNoFeedbackScore,
      ),
      completedHadBadConnection: List.generate(50, (_) => 0),
      completedWasInterrupted: List.generate(50, (_) => 0),
      feedbackAtEpochSec: List.generate(50, (i) => i + 2000),
      feedbackScores: List.generate(50, (i) => 5),
    );
    s = s.withMeetingCreated(9999);
    expect(s.createdAtEpochSec.length, 48);
    expect(s.completedAtEpochSec.length, 48);
    expect(s.completedFeedbackScores.length, 48);
    expect(s.completedHadBadConnection.length, 48);
    expect(s.completedWasInterrupted.length, 48);
    expect(s.feedbackAtEpochSec.length, 48);
    expect(s.feedbackScores.length, 48);
  });

  testUnit('withMeetingCreated trims created list to cap', () {
    UserActivityPersistedV1 state = const UserActivityPersistedV1();
    for (var i = 0; i < 50; i++) {
      state = state.withMeetingCreated(i);
    }
    expect(state.createdAtEpochSec.length, 48);
    expect(state.createdAtEpochSec.first, 2);
    expect(state.createdAtEpochSec.last, 49);
  });
}
