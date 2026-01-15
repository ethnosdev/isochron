import 'package:test/test.dart';
import 'package:isochron_cli/src/core/fragment.dart';
import 'package:isochron_cli/src/math/dtw_aligner.dart';
import 'package:isochron_cli/src/core/time_projector.dart'; // To be created

void main() {
  group('Time Projector', () {
    test('should map anchor timestamps to real timestamps via path', () {
      // 1. Setup Fragments
      // Anchor: Frag 1 (0.0 - 0.2), Frag 2 (0.2 - 0.4)
      final f1 = Fragment(index: 0, text: 'A')
        ..setAnchorTiming(start: 0.0, end: 0.2);
      final f2 = Fragment(index: 1, text: 'B')
        ..setAnchorTiming(start: 0.2, end: 0.4);
      final fragments = [f1, f2];

      // 2. Setup Path (Time Stretched)
      // Anchor Frame Stride = 0.1s (for simple math)
      // Real is 2x slower.
      // Anchor 0 -> Real 0
      // Anchor 1 -> Real 2
      // Anchor 2 -> Real 4
      final path = [
        AlignmentPoint(0, 0),
        AlignmentPoint(2, 1),
        AlignmentPoint(4, 2), // Frag 1 ends here (0.2s)
        AlignmentPoint(6, 3),
        AlignmentPoint(8, 4), // Frag 2 ends here (0.4s)
      ];

      // 3. Run Projector
      // We assume frame stride is 0.1s for this test logic to hold
      TimeProjector.project(fragments, path, frameStride: 0.1);

      // 4. Verify
      // Frag 1 End: Anchor 0.2s -> Frame 2. Path maps Anchor 2 to Real 4. Real 4 * 0.1 = 0.4s.
      expect(f1.realEnd, closeTo(0.4, 0.001));

      // Frag 2 Start: Anchor 0.2s -> Frame 2 -> Real 4 -> 0.4s
      expect(f2.realStart, closeTo(0.4, 0.001));

      // Frag 2 End: Anchor 0.4s -> Frame 4 -> Real 8 -> 0.8s
      expect(f2.realEnd, closeTo(0.8, 0.001));
    });
  });
}
