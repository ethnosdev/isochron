import 'package:isochron_cli/isochron_cli.dart';
import 'package:test/test.dart';

void main() {
  group('Vector Utils', () {
    test('euclideanDistance should be correct', () {
      final v1 = [0.0, 0.0];
      final v2 = [3.0, 4.0];

      // 3-4-5 triangle
      final dist = VectorUtils.euclideanDistance(v1, v2);
      expect(dist, closeTo(5.0, 0.001));
    });

    test('euclideanDistance should handle different dimensions gracefully', () {
      // In a perfect world, this shouldn't happen, but good to check
      final v1 = [1.0];
      final v2 = [3.0, 5.0];

      // Should throw or handle. Let's assume it throws for safety.
      expect(() => VectorUtils.euclideanDistance(v1, v2), throwsException);
    });
  });
}
