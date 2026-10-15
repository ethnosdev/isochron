import 'dart:typed_data';
import 'package:isochron_cli/src/mms/ctc_aligner.dart';
import 'package:isochron_cli/src/mms/onnx_emissions_engine.dart';
import 'package:test/test.dart';

void main() {
  group('CtcAligner', () {
    test('aligns synthetic sequence accurately', () {
      // 10 frames, 32 classes
      const numFrames = 10;
      final data = Float32List(numFrames * 32);
      // Fill with very low log-probs
      data.fillRange(0, data.length, -10.0);

      // We want to align tokens: [tokenA (id 4), tokenB (id 20)]
      // Frames 0..2: silence (blank id 0)
      for (var t = 0; t <= 2; t++) {
        data[t * 32 + 0] = 0.0;
      }
      // Frames 3..5: tokenA (id 4)
      for (var t = 3; t <= 5; t++) {
        data[t * 32 + 4] = 0.0;
      }
      // Frames 6..8: tokenB (id 20)
      for (var t = 6; t <= 8; t++) {
        data[t * 32 + 20] = 0.0;
      }
      // Frame 9: silence (blank id 0)
      data[9 * 32 + 0] = 0.0;

      final emissions = EmissionsOutput(data: data, totalFrames: numFrames);
      final result = CtcAligner.align(
        emissions: emissions,
        targetTokenIds: [4, 20],
        targetTokenChars: ['a', 'b'],
      );

      expect(result.tokenTimings.length, equals(2));
      final aTiming = result.tokenTimings[0];
      final bTiming = result.tokenTimings[1];

      expect(aTiming.startFrame, equals(3));
      expect(aTiming.endFrame, equals(6)); // 3, 4, 5 inclusive -> exclusive 6
      expect(bTiming.startFrame, equals(6));
      expect(bTiming.endFrame, equals(9)); // 6, 7, 8 inclusive -> exclusive 9
    });

    test('throws when trellis exceeds safety cell cap', () {
      final emissions = EmissionsOutput(data: Float32List(0), totalFrames: 1000000);
      expect(
        () => CtcAligner.align(
          emissions: emissions,
          targetTokenIds: List.filled(5000, 4),
          targetTokenChars: List.filled(5000, 'a'),
        ),
        throwsArgumentError,
      );
    });
  });
}
