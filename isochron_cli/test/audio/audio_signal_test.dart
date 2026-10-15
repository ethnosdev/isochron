import 'dart:math' as math;
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:isochron_cli/src/audio/audio_signal.dart';

void main() {
  group('AudioSignal', () {
    test('analyzes silence and sine wave correctly', () {
      const sampleRate = 16000;
      const durationSeconds = 1.0;
      final numSamples = (sampleRate * durationSeconds).toInt();
      final samples = Float32List(numSamples);

      // First 0.5s = silence (0.0), next 0.5s = 440 Hz sine wave with amplitude 0.5 (-6 dBFS peak)
      for (int i = numSamples ~/ 2; i < numSamples; i++) {
        final t = i / sampleRate;
        samples[i] = 0.5 * math.sin(2 * math.pi * 440 * t);
      }

      final signal = AudioSignal.analyze(samples, sampleRate: sampleRate);

      expect(signal.totalSeconds, closeTo(1.0, 0.001));
      expect(signal.frameEnergyDbfs.length, 100); // 100 frames of 10ms

      // First 50 frames should be near digital silence (-100 dBFS floor)
      expect(signal.frameEnergyDbfs[10], lessThan(-80.0));

      // Last 50 frames should be around -9 dBFS (RMS of 0.5 sine = 0.5 / sqrt(2) ≈ 0.3535 -> 20*log10(0.3535) ≈ -9.03 dBFS)
      expect(signal.frameEnergyDbfs[75], closeTo(-9.0, 1.0));

      // Noise floor (P15) should be in the silent region
      expect(signal.noiseFloorDbfs, lessThan(-70.0));

      // Speech level (P80) should reflect the active tone
      expect(signal.speechLevelDbfs, closeTo(-9.0, 1.0));

      // Adaptive threshold should be clamped within [-62, -36] dBFS
      expect(signal.silenceThresholdDbfs, greaterThanOrEqualTo(-62.0));
      expect(signal.silenceThresholdDbfs, lessThanOrEqualTo(-36.0));
    });

    test('frame index to seconds conversion', () {
      final samples = Float32List(16000);
      final signal = AudioSignal.analyze(samples, sampleRate: 16000, frameSizeMs: 10);

      expect(signal.frameToSeconds(0), 0.0);
      expect(signal.frameToSeconds(50), closeTo(0.50, 0.001));
      expect(signal.secondsToFrame(0.50), 50);
    });
  });
}
