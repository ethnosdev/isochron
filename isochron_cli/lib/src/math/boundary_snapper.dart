import 'dart:math';
import 'dart:typed_data';

class BoundarySnapper {
  /// Refines timestamps by looking for energy onsets in the real audio.
  /// [audio] should be the normalized float samples.
  /// [sampleRate] usually 16000.
  /// [snapOffsetMs] is subtracted from each snapped start time (onset mode only;
  /// callers pass 0 when not using onset snapping).
  static void snap(
    List<dynamic> fragments,
    Float64List audio,
    int sampleRate, {
    int snapOffsetMs = 0,
  }) {
    const double windowSec = 0.25; // Look +/- 250ms
    final int windowSamples = (windowSec * sampleRate).round();

    // Threshold: Calculate noise floor of the file to determine "Silence"
    double noiseFloor = 0.0;
    // Sample first 0.5s for noise floor
    int noiseSamples = min(audio.length, sampleRate ~/ 2);
    for (int i = 0; i < noiseSamples; i++) {
      noiseFloor += audio[i].abs();
    }
    noiseFloor = (noiseFloor / noiseSamples) * 1.5; // 1.5x average noise
    for (final (i, frag) in fragments.indexed) {
      // Skip fragments whose timings were user-verified — don't move them.
      if (frag.isPinned) continue;

      // 1. Snap Start Time
      int originalStartIndex = (frag.realStart * sampleRate).round();
      int searchStart = max(0, originalStartIndex - windowSamples);
      int searchEnd = min(audio.length, originalStartIndex + windowSamples);

      int bestIndex = originalStartIndex;

      // Look for the first moment energy crosses threshold
      for (int i = searchStart; i < searchEnd - 100; i++) {
        // Calculate local energy (short window)
        double localEnergy = 0.0;
        for (int j = 0; j < 100; j++) {
          localEnergy += audio[i + j].abs();
        }
        localEnergy /= 100;

        if (localEnergy > noiseFloor) {
          bestIndex = i;
          // shift back by half the time since the silence onset, but not less than 0
          int shiftAmount = ((i - searchStart) / 2).round();
          bestIndex = max(0, bestIndex - shiftAmount);
          break; // Found the onset!
        }
      }

      // Only apply if it makes sense (don't snap wildly far)
      if ((bestIndex - originalStartIndex).abs() < windowSamples) {
        final double offsetSec = snapOffsetMs / 1000.0;
        double startSec = (bestIndex / sampleRate) - offsetSec;
        if (startSec < 0) startSec = 0;
        frag.setRealTiming(
            start: startSec,
            end: frag
                .realEnd // Leave end alone, or apply similar logic backwards
            );
        if (i > 0) {
          final prev = fragments[i - 1];
          if (!prev.isPinned) {
            prev.setRealTiming(start: prev.realStart, end: startSec);
          }
        }
      }
    }
  }
}
