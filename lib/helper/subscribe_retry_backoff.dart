import 'dart:math';

/// Exponential subscribe retry backoff with symmetric ± [subscribeRetryJitterFraction] jitter.
Duration subscribeRetryBackoffWithJitter({
  required Duration baseDelay,
  required int retryIndex,
  Duration? maxDelay,
}) {
  final multiplier = 1 << retryIndex;
  var backoffMs = baseDelay.inMilliseconds * multiplier;
  if (maxDelay != null) {
    backoffMs = min(backoffMs, maxDelay.inMilliseconds);
  }

  final jitterRange = (backoffMs * 0.2).round(); // ±20% jitter
  final rng = Random.secure();
  final jitter = jitterRange == 0
      ? 0
      : rng.nextInt(jitterRange * 2 + 1) - jitterRange;
  return Duration(milliseconds: max(0, backoffMs + jitter));
}
