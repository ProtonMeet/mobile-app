// Layout math for screen-wide emoji reaction animations (parity with web ReactionStream).

/// Upper bound so a burst of reactions cannot flood the widget tree.
const int kReactionStreamMaxVisible = 30;

/// Rise + appear duration (web: 4.2s).
const Duration kReactionStreamAnimationDuration = Duration(milliseconds: 4200);

/// Reduced-motion fade duration (web: 3s).
const Duration kReactionStreamReducedMotionDuration = Duration(
  milliseconds: 3000,
);

/// Distance from the bottom edge to the reaction anchor (web: 6rem above controls).
const double kReactionStreamBottomInset = 96;

/// Emoji size (web: 2.75rem).
const double kReactionStreamEmojiSize = 44;

/// Name pill max width (web: 10rem).
const double kReactionStreamNameMaxWidth = 160;

class ReactionStreamItemData {
  const ReactionStreamItemData({
    required this.id,
    required this.identity,
    required this.emoji,
    required this.leftPercent,
    required this.driftPx,
    required this.riseVh,
  });

  final String id;
  final String identity;
  final String emoji;
  final double leftPercent;
  final double driftPx;
  final double riseVh;
}

/// FNV-1a → [0, 1). Positions are derived from the reaction id for reproducibility.
double reactionStreamHashToUnit(String value, int salt) {
  var hash = 2166136261 ^ salt;
  for (final codeUnit in value.codeUnits) {
    hash = (hash ^ codeUnit) * 16777619;
    hash = hash & 0xFFFFFFFF;
  }
  return hash / 4294967296;
}

double _between(double unit, double min, double max) =>
    min + unit * (max - min);

ReactionStreamItemData createReactionStreamItem({
  required String identity,
  required String emoji,
  required int timestamp,
}) {
  final id = '$identity-$timestamp';
  double unit(int salt) => reactionStreamHashToUnit(id, salt);

  return ReactionStreamItemData(
    id: id,
    identity: identity,
    emoji: emoji,
    leftPercent: _between(unit(1), 3, 25),
    driftPx: _between(unit(2), 10, 24) * (unit(3) < 0.5 ? -1 : 1),
    riseVh: _between(unit(4), 50, 65),
  );
}

/// Opacity keyframes for the appear animation (web reaction-stream-appear).
double reactionStreamAppearOpacity(double t) {
  if (t <= 0.06) {
    return t / 0.06;
  }
  if (t <= 0.80) {
    return 1;
  }
  return 1 - (t - 0.80) / 0.20;
}

/// Scale keyframes for the appear animation (web reaction-stream-appear).
double reactionStreamAppearScale(double t) {
  if (t <= 0.06) {
    return 0.6 + (1 - 0.6) * (t / 0.06);
  }
  if (t <= 0.80) {
    return 1;
  }
  return 1 - (1 - 0.95) * ((t - 0.80) / 0.20);
}

/// Opacity keyframes for reduced-motion fade (web reaction-stream-fade).
double reactionStreamReducedMotionOpacity(double t) {
  if (t <= 0.10) {
    return t / 0.10;
  }
  if (t <= 0.80) {
    return 1;
  }
  return 1 - (t - 0.80) / 0.20;
}
