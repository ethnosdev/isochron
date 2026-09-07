import 'dart:math';
import 'dart:typed_data';
import 'vector_utils.dart';

// Directions for backtracking
const int _dirDiag = 1; // Match (i-1, j-1)
const int _dirUp = 2; // Insertion (i-1, j)
const int _dirLeft = 3; // Deletion (i, j-1)

typedef ProgressCallback = void Function(String status, double percentage);

class AlignmentPoint {
  final int realIndex;
  final int anchorIndex;
  AlignmentPoint(this.realIndex, this.anchorIndex);
}

class DtwAligner {
  /// Optimized DTW using a sliding window for costs and a flat Uint8List for path history.
  /// Drastically reduces memory usage from O(N*M) to O(N*Radius).
  static List<AlignmentPoint> align(
    List<List<double>> realSeq,
    List<List<double>> anchorSeq, {
    int? radius, // Optional manual override. If omitted, adaptively sized (5% of length, min 25s)
    ProgressCallback? onProgress,
  }) {
    final int N = realSeq.length;
    final int M = anchorSeq.length;

    if (N == 0 || M == 0) return [];
    if (N == 1 && M == 1) return [AlignmentPoint(0, 0)];

    // 1. Determine Radius
    // In slope-constrained DTW, the center line jCenter = (i * M / N).round()
    // already connects (0, 0) to (N - 1, M - 1). The radius only needs to
    // accommodate local pacing drift around the average rate.
    // Adaptive radius: 5% of sequence length with a minimum 25-second (2500 frames) buffer.
    final int maxDimension = max(N, M);
    final int calculatedRadius = (radius != null && radius > 0)
        ? radius
        : max(2500, (maxDimension * 0.05).round());
    final int r = max(1, min(calculatedRadius, maxDimension));

    // The "Band Width" determines our memory block size.
    // We map the diagonal band into a flat rectangle of width (2*r + 1).
    final int width = 2 * r + 1;

    // 2. Memory Allocation
    // Backtrack Matrix: Stores directions (1 byte per cell).
    final backtrack = Uint8List(N * width);

    // Cost Rows: We only keep two rows in memory (Previous and Current).
    // Using Float64List for speed.
    var prevCost = Float64List(M)..fillRange(0, M, double.infinity);
    var currCost = Float64List(M)..fillRange(0, M, double.infinity);

    // Initialize (0,0)
    final startDist = VectorUtils.euclideanDistance(realSeq[0], anchorSeq[0]);
    prevCost[0] = startDist;

    final int reportStep = max(1, (N / 100).ceil());

    int prevPrevStart = 0;
    int prevPrevEnd = 0;
    int prevStart = 0;
    int prevEnd = 0;

    // 3. Forward Pass (Calculate Costs)
    for (int i = 1; i < N; i++) {
      // Progress Report
      if (onProgress != null && i % reportStep == 0) {
        onProgress('Aligning...', i / N);
      }

      // Calculate the "Center" of the band for this row (slope)
      final int jCenter = (i * M / N).round();
      final int jStart = max(1, jCenter - r);
      final int jEnd = min(M - 1, jCenter + r);

      // Reset only the range modified during this buffer's previous turn
      if (prevPrevEnd >= prevPrevStart) {
        currCost.fillRange(
            prevPrevStart, min(M, prevPrevEnd + 1), double.infinity);
      }

      for (int j = jStart; j <= jEnd; j++) {
        final double dist =
            VectorUtils.euclideanDistance(realSeq[i], anchorSeq[j]);

        // Predecessors
        final double diag = prevCost[j - 1];
        final double up = prevCost[j];
        final double left = currCost[j - 1];

        if (diag == double.infinity &&
            up == double.infinity &&
            left == double.infinity) {
          continue; // No valid path to here
        }

        // Find min cost and direction
        double minVal = diag;
        int direction = _dirDiag;

        if (up < minVal) {
          minVal = up;
          direction = _dirUp;
        }
        if (left < minVal) {
          minVal = left;
          direction = _dirLeft;
        }

        currCost[j] = dist + minVal;

        // Store direction in compact matrix
        // Mapping: index = i * width + (j - jCenter + r)
        // This maps the slanted band into a straight vertical column in memory.
        final int storageCol = j - jCenter + r;
        if (storageCol >= 0 && storageCol < width) {
          backtrack[i * width + storageCol] = direction;
        }
      }

      prevPrevStart = prevStart;
      prevPrevEnd = prevEnd;
      prevStart = jStart;
      prevEnd = jEnd;

      // Swap buffers (curr becomes prev for next iteration)
      final temp = prevCost;
      prevCost = currCost;
      currCost = temp;
    }

    if (onProgress != null) onProgress('Backtracking...', 1.0);

    // 4. Backward Pass (Trace Path)
    final List<AlignmentPoint> path = [];
    int i = N - 1;
    int j = M - 1;

    path.add(AlignmentPoint(i, j));

    while (i > 0 && j > 0) {
      // Re-calculate the storage index for this coordinate
      final int jCenter = (i * M / N).round();
      final int storageCol = j - jCenter + r;

      // If we drift out of the calculated band, force a diagonal step (safety)
      int direction = _dirDiag;

      if (storageCol >= 0 && storageCol < width) {
        direction = backtrack[i * width + storageCol];
      }

      if (direction == _dirDiag) {
        i--;
        j--;
      } else if (direction == _dirUp) {
        i--;
      } else if (direction == _dirLeft) {
        j--;
      } else {
        // Should not happen if logic is correct, but safe fallback
        i--;
        j--;
      }

      path.add(AlignmentPoint(i, j));
    }

    return path.reversed.toList();
  }
}
