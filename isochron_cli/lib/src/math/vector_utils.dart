import 'dart:math';

class VectorUtils {
  /// Calculates Euclidean distance between two vectors.
  /// SQRT( SUM( (a[i] - b[i])^2 ) )
  static double euclideanDistance(List<double> v1, List<double> v2) {
    if (v1.length != v2.length) {
      throw Exception(
          'Vector dimension mismatch: ${v1.length} vs ${v2.length}');
    }

    double sum = 0.0;
    for (int i = 0; i < v1.length; i++) {
      final diff = v1[i] - v2[i];
      sum += diff * diff;
    }
    return sqrt(sum);
  }
}
