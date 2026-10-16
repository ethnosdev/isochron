import 'dart:math' as math;
import '../audio/pause_detector.dart';

/// Snaps raw CTC boundaries to nearby acoustic pauses.
class PauseSnapper {
  final double searchWindowSeconds;
  final double leadInSeconds;
  final double maxPauseFraction;
  final double minVerseDurationSeconds;

  const PauseSnapper({
    this.searchWindowSeconds = 1.0,
    this.leadInSeconds = 0.19,
    this.maxPauseFraction = 0.65,
    this.minVerseDurationSeconds = 0.150,
  });

  /// Snaps a list of [boundaries] (in seconds) to the nearest qualifying [pauses].
  /// Preserves monotonicity and contiguity without collapsing distinct verses.
  List<double> snapBoundaries(
    List<double> boundaries,
    List<AudioPause> pauses, {
    List<double>? speechStarts,
  }) {
    if (boundaries.isEmpty) return [];
    if (pauses.isEmpty) return List<double>.from(boundaries);

    final result = List<double>.filled(boundaries.length, -1.0);
    final claimedPauseEnds = <double>{};

    for (int i = 0; i < boundaries.length; i++) {
      final t = boundaries[i];
      if (t < 0) {
        result[i] = -1.0;
        continue;
      }

      int? prevIdx;
      for (int k = i - 1; k >= 0; k--) {
        if (result[k] >= 0) {
          prevIdx = k;
          break;
        }
      }

      final double lowerBound = prevIdx != null
          ? result[prevIdx] + minVerseDurationSeconds
          : 0.0;

      int? nextIdx;
      for (int k = i + 1; k < boundaries.length; k++) {
        if (boundaries[k] >= 0) {
          nextIdx = k;
          break;
        }
      }

      final double upperBound = nextIdx != null
          ? (speechStarts != null && nextIdx < speechStarts.length && speechStarts[nextIdx] >= 0
              ? speechStarts[nextIdx]
              : boundaries[nextIdx] - minVerseDurationSeconds)
          : double.infinity;

      double effectiveWindow = searchWindowSeconds;
      if (prevIdx != null) {
        effectiveWindow = math.min(effectiveWindow, (t - result[prevIdx]) * 0.45);
      }
      if (nextIdx != null) {
        effectiveWindow = math.min(effectiveWindow, (boundaries[nextIdx] - t) * 0.45);
      }
      effectiveWindow = math.max(0.05, effectiveWindow);

      AudioPause? bestPause;
      double minScore = double.infinity;

      for (final p in pauses) {
        if (p.endSeconds <= lowerBound || p.startSeconds >= upperBound) {
          continue;
        }
        if (claimedPauseEnds.contains(p.endSeconds)) {
          continue;
        }

        double dist;
        if (t >= p.startSeconds && t <= p.endSeconds) {
          dist = 0.0;
        } else if (t < p.startSeconds) {
          dist = p.startSeconds - t;
        } else {
          dist = t - p.endSeconds;
        }

        if (dist <= effectiveWindow) {
          final score = dist + (t - p.endSeconds).abs() * 0.1;
          if (score < minScore) {
            minScore = score;
            bestPause = p;
          }
        }
      }

      if (bestPause != null) {
        final p = bestPause;
        final candidate = p.endSeconds - leadInSeconds;
        final minSafeStart = p.startSeconds + (1.0 - maxPauseFraction) * p.durationSeconds;
        final snapped = math.max(candidate, minSafeStart);

        if (snapped >= lowerBound && snapped < upperBound) {
          result[i] = snapped;
          claimedPauseEnds.add(p.endSeconds);
        } else {
          result[i] = math.max(lowerBound, t);
        }
      } else {
        result[i] = math.max(lowerBound, t);
      }
    }

    // Monotonicity enforcement with minimum verse duration
    for (int i = 1; i < result.length; i++) {
      if (result[i] >= 0 &&
          result[i - 1] >= 0 &&
          result[i] < result[i - 1] + minVerseDurationSeconds) {
        result[i] = result[i - 1] + minVerseDurationSeconds;
      }
    }

    return result;
  }
}
