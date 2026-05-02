import 'dart:math';
import 'dart:typed_data';

import '../../core/boundary_strategy.dart';
import '../../core/fragment.dart';
import 'normalized_peak_bins.dart';

/// Shared configuration values for boundary snapping.
///
/// These constants are kept in one place to avoid magic numbers scattered
/// across strategies.
class BoundarySnappingConfig {
  /// Size used when converting raw audio into normalized peak bins.
  static const double binSizeMs = NormalizedPeakBins.defaultBinSizeMs;

  /// Normalized silence threshold [0..1].
  static const double silenceThreshold =
      NormalizedPeakBins.defaultSilenceThreshold;
}

/// Gap-based snapping: adjust boundaries toward the center of the
/// lowest-energy region between neighbouring fragments.
class GapBasedBoundarySnapStrategy implements BoundarySnapStrategy {
  const GapBasedBoundarySnapStrategy();

  @override
  void snap({
    required List<Fragment> fragments,
    required Float64List audio,
    required int sampleRate,
  }) {
    if (fragments.length < 2 || audio.isEmpty || sampleRate <= 0) {
      return;
    }

    final peaks = NormalizedPeakBins.fromRawAudio(
      audio,
      sampleRate,
      binSizeMs: BoundarySnappingConfig.binSizeMs,
    );
    if (peaks.isEmpty) return;
    final silenceRuns = SilenceRunSelector.findSilenceRuns(
      peaks,
      silenceThreshold: BoundarySnappingConfig.silenceThreshold,
    );
    if (silenceRuns.isEmpty) return;

    for (int i = 0; i < fragments.length - 1; i++) {
      final Fragment left = fragments[i];
      final Fragment right = fragments[i + 1];

      // Respect user-provided pins. When a fragment is pinned, only adjust the
      // unpinned side of the boundary. When both are pinned, leave as-is.
      if (left.isPinned && right.isPinned) continue;

      final int leftEndSample =
          (left.realEnd * sampleRate).round().clamp(0, audio.length);
      final int rightStartSample =
          (right.realStart * sampleRate).round().clamp(0, audio.length);

      // If projection has produced an inverted boundary, skip it.
      // Equal boundaries are expected in contiguous timelines, so we still
      // refine around that seam.
      if (rightStartSample < leftEndSample) {
        continue;
      }

      final int boundaryCenterSample =
          leftEndSample + ((rightStartSample - leftEndSample) ~/ 2);
      final int seamBin =
          ((boundaryCenterSample / audio.length) * peaks.length).round().clamp(
                0,
                peaks.length - 1,
              );

      final silenceRegion = SilenceRunSelector.pickRunForSeam(
        silenceRuns,
        seamBin,
      );
      if (silenceRegion == null) continue;

      final int midBin = silenceRegion.startBin +
          ((silenceRegion.endBin - silenceRegion.startBin) ~/ 2);
      final double snappedTimeSeconds =
          (midBin / peaks.length) * (audio.length / sampleRate);

      // Resolve one shared boundary value, then apply it to whichever side can
      // move. This guarantees both fragment edges meet at exactly one time.
      final bool leftPinned = left.isPinned;
      final bool rightPinned = right.isPinned;

      double resolvedBoundarySeconds;
      if (leftPinned) {
        resolvedBoundarySeconds = left.realEnd;
      } else if (rightPinned) {
        resolvedBoundarySeconds = right.realStart;
      } else {
        final double lowerBound = left.realStart;
        final double upperBound = right.realEnd;
        resolvedBoundarySeconds =
            min(max(snappedTimeSeconds, lowerBound), upperBound);
      }

      if (!leftPinned) {
        left.realEnd = resolvedBoundarySeconds;
      }

      if (!rightPinned) {
        right.realStart = resolvedBoundarySeconds;
      }
    }
  }
}
