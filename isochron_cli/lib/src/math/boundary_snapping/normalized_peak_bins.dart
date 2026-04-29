import 'dart:math';
import 'dart:typed_data';

class NormalizedPeakBins {
  const NormalizedPeakBins._();

  static const double defaultSilenceThreshold = 0.035;
  static const double defaultBinSizeMs = 10.0;

  static List<double> fromRawAudio(
    Float64List audio,
    int sampleRate, {
    double binSizeMs = defaultBinSizeMs,
  }) {
    if (audio.isEmpty || sampleRate <= 0) return const [];
    final int samplesPerBin = max(1, ((binSizeMs / 1000.0) * sampleRate).round());
    final List<double> peaks = [];

    for (int i = 0; i < audio.length; i += samplesPerBin) {
      final int end = min(audio.length, i + samplesPerBin);
      double peak = 0.0;
      for (int j = i; j < end; j++) {
        final amp = audio[j].abs();
        if (amp > peak) peak = amp;
      }
      peaks.add(peak.clamp(0.0, 1.0));
    }

    return peaks;
  }

  static double fromWaveformMinMax(
    int sampleMin,
    int sampleMax, {
    required bool is16Bit,
  }) {
    final int peak = max(sampleMin.abs(), sampleMax.abs());
    final double fullScale = is16Bit ? 32768.0 : 128.0;
    return (peak / fullScale).clamp(0.0, 1.0);
  }
}

class SilenceRunSelector {
  const SilenceRunSelector._();

  static List<({int startBin, int endBin})> findSilenceRuns(
    List<double> normalizedPeaks, {
    double silenceThreshold = NormalizedPeakBins.defaultSilenceThreshold,
  }) {
    final runs = <({int startBin, int endBin})>[];
    bool inRun = false;
    int runStart = 0;

    for (int i = 0; i < normalizedPeaks.length; i++) {
      final bool isSilence = normalizedPeaks[i] <= silenceThreshold;
      if (isSilence && !inRun) {
        inRun = true;
        runStart = i;
      } else if (!isSilence && inRun) {
        inRun = false;
        runs.add((startBin: runStart, endBin: i - 1));
      }
    }

    if (inRun) {
      runs.add((startBin: runStart, endBin: normalizedPeaks.length - 1));
    }
    return runs;
  }

  static ({int startBin, int endBin})? pickRunForSeam(
    List<({int startBin, int endBin})> runs,
    int seamBin,
  ) {
    if (runs.isEmpty) return null;

    for (final run in runs) {
      if (run.startBin <= seamBin && seamBin <= run.endBin) return run;
    }

    ({int startBin, int endBin})? bestBefore;
    for (final run in runs) {
      if (run.endBin <= seamBin &&
          (bestBefore == null || run.endBin > bestBefore.endBin)) {
        bestBefore = run;
      }
    }
    if (bestBefore != null) return bestBefore;

    ({int startBin, int endBin})? bestAfter;
    for (final run in runs) {
      if (run.startBin >= seamBin &&
          (bestAfter == null || run.startBin < bestAfter.startBin)) {
        bestAfter = run;
      }
    }
    return bestAfter;
  }
}

