import 'package:test/test.dart';
import 'package:isochron_cli/src/math/dtw_aligner.dart'; // To be created

void main() {
  group('DTW Aligner', () {
    test('should align identical sequences perfectly diagonally', () {
      // Simple 1D vectors for testing
      final seq1 = [
        [1.0],
        [2.0],
        [3.0]
      ]; // Real
      final seq2 = [
        [1.0],
        [2.0],
        [3.0]
      ]; // Anchor

      final path = DtwAligner.align(seq1, seq2);

      // Expecting [(0,0), (1,1), (2,2)]
      expect(path.length, 3);
      expect(path.first.realIndex, 0);
      expect(path.first.anchorIndex, 0);
      expect(path.last.realIndex, 2);
      expect(path.last.anchorIndex, 2);
    });

    test('should handle time stretching (one sequence slower)', () {
      // Real:   1, 1, 2, 3 (Spoke "1" slowly)
      // Anchor: 1, 2, 3
      final seq1 = [
        [1.0],
        [1.0],
        [2.0],
        [3.0]
      ];
      final seq2 = [
        [1.0],
        [2.0],
        [3.0]
      ];

      final path = DtwAligner.align(seq1, seq2);

      // Path length should match the longer sequence (roughly)
      expect(path.length, greaterThanOrEqualTo(4));

      // Verify start and end match
      expect(path.first.realIndex, 0);
      expect(path.first.anchorIndex, 0);
      expect(path.last.realIndex, 3);
      expect(path.last.anchorIndex, 2);
    });
  });
}
