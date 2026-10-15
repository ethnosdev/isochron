import 'dart:math' as math;
import '../audio/pause_detector.dart';

/// Snaps raw CTC boundaries to nearby acoustic pauses.
class PauseSnapper {
  final double searchWindowSeconds;
  final double leadInSeconds;
  final double maxPauseFraction;

  const PauseSnapper({
    this.searchWindowSeconds = 1.0,
    this.leadInSeconds = 0.19,
    this.maxPauseFraction = 0.65,
  });

  /// Snaps a list of [boundaries] (in seconds) to the nearest qualifying [pauses].
  /// Preserves monotonicity and contiguity.
  List<double> snapBoundaries(
    List<double> boundaries,
    List<AudioPause> pauses,
  ) {
    if (boundaries.isEmpty) return [];
    if (pauses.isEmpty) return List<double>.from(boundaries);

    final result = List<double>.filled(boundaries.length, 0.0);

    for (int i = 0; i < boundaries.length; i++) {
      final t = boundaries[i];
      if (t < 0) {
        result[i] = t;
        continue;
      }

      // Search for candidate pauses within [t - searchWindowSeconds, t + searchWindowSeconds]
      AudioPause? bestPause;
      double minDistance = double.infinity;

      for (final p in pauses) {
        // Distance from t to the pause interval
        double dist;
        if (t >= p.startSeconds && t <= p.endSeconds) {
          dist = 0.0;
        } else if (t < p.startSeconds) {
          dist = p.startSeconds - t;
        } else {
          dist = t - p.endSeconds;
        }

        if (dist <= searchWindowSeconds) {
          // Weight pauses containing t or closer to speech onset
          final score = dist + (t - p.endSeconds).abs() * 0.1;
          if (score < minDistance) {
            minDistance = score;
            bestPause = p;
          }
        }
      }

      if (bestPause != null) {
        final p = bestPause;
        final candidate = p.endSeconds - leadInSeconds;
        final minSafeStart = p.startSeconds + (1.0 - maxPauseFraction) * p.durationSeconds;
        final snapped = math.max(candidate, minSafeStart);
        result[i] = snapped;
      } else {
        result[i] = t;
      }
    }

    // Monotonicity enforcement: boundaries must be non-decreasing
    for (int i = 1; i < result.length; i++) {
      if (result[i] >= 0 && result[i - 1] >= 0 && result[i] < result[i - 1]) {
        result[i] = result[i - 1];
      }
    }

    return result;
  }
}
