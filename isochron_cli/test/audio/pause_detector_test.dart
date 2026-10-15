import 'dart:math' as math;
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:isochron_cli/src/audio/audio_signal.dart';
import 'package:isochron_cli/src/audio/pause_detector.dart';

void main() {
  group('PauseDetector', () {
    test('detects qualifying silence pause between speech bursts', () {
      const sampleRate = 16000;
      // Total 3.0 seconds:
      // 0.0 - 1.0s: burst 1 (loud)
      // 1.0 - 1.5s: pause (silence, 500 ms)
      // 1.5 - 2.0s: burst 2 (loud)
      // 2.0 - 2.04s: micro-dip (40 ms silence, stop consonant)
      // 2.04 - 3.0s: burst 3 (loud)
      final numSamples = (sampleRate * 3.0).toInt();
      final samples = Float32List(numSamples);

      for (int i = 0; i < numSamples; i++) {
        final t = i / sampleRate;
        final isPause = (t >= 1.0 && t < 1.5);
        final isMicroDip = (t >= 2.0 && t < 2.04);

        if (!isPause && !isMicroDip) {
          samples[i] = 0.5 * math.sin(2 * math.pi * 440 * t);
        }
      }

      final signal = AudioSignal.analyze(samples, sampleRate: sampleRate);
      const detector = PauseDetector(minDurationSeconds: 0.100);
      final pauses = detector.detectPauses(signal);

      // Should detect the 500ms pause, but ignore the 40ms micro-dip
      expect(pauses.length, 1);
      final p = pauses.first;
      expect(p.startSeconds, closeTo(1.0, 0.02));
      expect(p.endSeconds, closeTo(1.5, 0.02));
      expect(p.durationSeconds, closeTo(0.5, 0.02));
      expect(p.minEnergyDbfs, lessThan(-60.0));
    });
  });
}
