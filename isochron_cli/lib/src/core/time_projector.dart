import 'fragment.dart';
import '../math/dtw_aligner.dart';

class TimeProjector {
  /// Maps anchor timestamps in [fragments] to real timestamps using the [path].
  static void project(List<Fragment> fragments, List<AlignmentPoint> path,
      {double frameStride = 0.010}) {
    // 1. Index the path for O(1) lookup?
    // DTW path is ordered, but might have duplicates.
    // A linear scan is O(N), but we have M fragments. O(M*N) is fine for typically small N.
    // For optimization, we can just walk the path index forward since fragments are ordered.

    int pathIndex = 0;

    for (final frag in fragments) {
      final anchorStartFrame = (frag.anchorStart / frameStride).round();

      // Find the first point in path where anchorIndex >= anchorStartFrame
      while (pathIndex < path.length &&
          path[pathIndex].anchorIndex < anchorStartFrame) {
        pathIndex++;
      }
      if (pathIndex >= path.length) {
        pathIndex = path.length - 1;
      }

      final startPoint = path[pathIndex];
      final realStart = startPoint.realIndex * frameStride;
      final anchorEndFrame = (frag.anchorEnd / frameStride).round();

      // Find the point corresponding to end.
      // We continue from current pathIndex.
      while (pathIndex < path.length &&
          path[pathIndex].anchorIndex < anchorEndFrame) {
        pathIndex++;
      }
      // If we overshot or hit end
      int endPathIndex = pathIndex;
      if (endPathIndex >= path.length) {
        endPathIndex = path.length - 1;
      }

      final endPoint = path[endPathIndex];
      final realEnd = endPoint.realIndex * frameStride;

      frag.setRealTiming(start: realStart, end: realEnd);
    }
  }
}
