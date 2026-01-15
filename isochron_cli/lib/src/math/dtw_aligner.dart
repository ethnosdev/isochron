import 'dart:math';
import 'vector_utils.dart';

/// Represents a single point of alignment between the two files.
class AlignmentPoint {
  final int realIndex;
  final int anchorIndex;

  AlignmentPoint(this.realIndex, this.anchorIndex);

  @override
  String toString() => '($realIndex, $anchorIndex)';
}

typedef ProgressCallback = void Function(String status, double percentage);

class DtwAligner {
  /// Aligns two sequences of feature vectors.
  ///
  /// [radius]: The Sakoe-Chiba band radius.
  /// Only searches `i - radius < j < i + radius`.
  /// Defaults to -1 (Auto-calculate ~10% of length).
  static List<AlignmentPoint> align(
      List<List<double>> realSeq, List<List<double>> anchorSeq,
      {int radius = -1, ProgressCallback? onProgress}) {
    final int N = realSeq.length;
    final int M = anchorSeq.length;

    // 1. Determine Radius
    // If not set, use 10% of the longer sequence, or at least 50 frames.
    int r = radius;
    if (r < 0) {
      r = (max(N, M) * 0.1).ceil();
      if (r < 50) r = 50;
    }
    // Absolute minimum to ensure corners (0,0) and (N,M) are reachable
    r = max(r, (N - M).abs() + 5);

    // 2. The Cost Matrix (Sparse)
    // We use a Map<int, Map<int, double>> to store accumulated costs.
    // Key: realIndex -> { anchorIndex: cost }
    final Map<int, Map<int, double>> accumulatedCost = {};

    // Helper to get cost safely (returns Infinity if not in band)
    double getCost(int i, int j) {
      if (i < 0 || j < 0) return double.infinity;
      return accumulatedCost[i]?[j] ?? double.infinity;
    }

    // Helper to set cost
    void setCost(int i, int j, double val) {
      if (!accumulatedCost.containsKey(i)) {
        accumulatedCost[i] = {};
      }
      accumulatedCost[i]![j] = val;
    }

    // 3. Forward Pass: Calculate Costs
    setCost(0, 0, VectorUtils.euclideanDistance(realSeq[0], anchorSeq[0]));

    int reportStep = (N / 100).ceil();

    for (int i = 0; i < N; i++) {
      if (onProgress != null && i % reportStep == 0) {
        // Map 0..N to 0.0..1.0 range
        onProgress('Aligning Matrices...', i / N);
      }

      // Define Band Limits for this row
      // We want j to be roughly around (i * M / N)
      // strictly enforcing |i - j| < radius is valid for equal lengths,
      // but for N != M, we align along the diagonal slope.
      //
      // Slope formula: j_center = i * (M / N)
      final int jCenter = (i * (M / N)).round();
      final int jStart = max(0, jCenter - r);
      final int jEnd = min(M, jCenter + r);

      for (int j = jStart; j < jEnd; j++) {
        // Skip (0,0) as it's already set
        if (i == 0 && j == 0) continue;

        final double dist =
            VectorUtils.euclideanDistance(realSeq[i], anchorSeq[j]);

        // Predecessors:
        // (i-1, j)   -> Insertion
        // (i, j-1)   -> Deletion
        // (i-1, j-1) -> Match
        final double costIm1j = getCost(i - 1, j);
        final double costIj1 = getCost(i, j - 1);
        final double costIm1j1 = getCost(i - 1, j - 1);

        final double minPrev = min(costIm1j, min(costIj1, costIm1j1));

        if (minPrev.isInfinite) {
          // If all predecessors are infinite, this cell is unreachable
          continue;
        }

        setCost(i, j, dist + minPrev);
      }
    }

    // Ensure we report 100% at the end
    if (onProgress != null) onProgress('Backtracking path...', 1.0);

    // 4. Backward Pass: Trace Path
    // Start from (N-1, M-1)
    final List<AlignmentPoint> path = [];
    int i = N - 1;
    int j = M - 1;

    path.add(AlignmentPoint(i, j));

    while (i > 0 || j > 0) {
      // Check neighbors
      final double diag = getCost(i - 1, j - 1); // Prefer diagonal usually
      final double up = getCost(i - 1, j);
      final double left = getCost(i, j - 1);

      // Greedy logic: pick lowest cost neighbor
      if (diag <= up && diag <= left) {
        i--;
        j--;
      } else if (up <= left) {
        i--;
      } else {
        j--;
      }
      path.add(AlignmentPoint(i, j));
    }

    // 5. Reverse to get chronological order
    return path.reversed.toList();
  }
}
