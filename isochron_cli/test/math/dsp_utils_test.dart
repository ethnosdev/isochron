import 'dart:math';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:isochron_cli/src/math/dsp_utils.dart'; // We will create this

void main() {
  group('DSP Utils', () {
    test('hzToMel and melToHz should be reversible', () {
      const hz = 1000.0;
      final mel = DspUtils.hzToMel(hz);
      final backToHz = DspUtils.melToHz(mel);

      // Allow small floating point error
      expect(backToHz, closeTo(hz, 0.1));
    });

    test('hammingWindow should create a bell curve', () {
      // Use an odd number (11) so the center falls exactly on an integer index (5)
      final window = DspUtils.createHammingWindow(11);
      expect(window.length, 11);

      // Edges should be small (0.08)
      expect(window.first, closeTo(0.08, 0.01));
      expect(window.last, closeTo(0.08, 0.01));

      // Center (index 5) should be max (1.0)
      expect(window[5], closeTo(1.0, 0.01));
    });

    test('DCT should function (basic check)', () {
      // A constant signal [1, 1, 1, 1]
      // DC component (index 0) should be high, others 0
      final input = Float64List.fromList([1.0, 1.0, 1.0, 1.0]);
      final output = DspUtils.dct(input);

      expect(output[0], greaterThan(0));
      expect(output[1], closeTo(0, 0.001));
    });
  });
}
