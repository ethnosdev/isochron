import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:isochron_cli/src/math/mfcc_extractor.dart'; // We will create this

void main() {
  group('MFCC Extractor', () {
    test('should extract features from silence', () {
      // 16000 samples = 1 second of audio
      final silence = Float64List(16000);

      final features = MfccExtractor.extract(silence);

      // We expect some frames.
      // 1000ms audio / 10ms stride = ~100 frames.
      expect(features.length, closeTo(99, 5));

      // Each frame should have 13 coefficients
      expect(features.first.length, 13);

      // Silence implies very low energy (negative log values) or zeros depending on handling
      // We just check structure here.
    });

    test('should slice audio into frames correctly', () {
      // A small helper method inside Extractor usually does this,
      // but we test the public interface.

      // 30ms of audio (480 samples at 16k).
      // Window 20ms (320), Stride 10ms (160).
      // Frame 1: 0-320
      // Frame 2: 160-480
      // Should result in exactly 2 frames.
      final audio = Float64List(480);
      final features = MfccExtractor.extract(audio);
      expect(features.length, 2);
    });
  });
}
