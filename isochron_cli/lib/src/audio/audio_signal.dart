import 'dart:math' as math;
import 'dart:typed_data';

/// Analysis of 16 kHz mono audio signal energy for pause detection and VAD.
class AudioSignal {
  final Float32List samples;
  final int sampleRate;
  final int frameSize; // 160 samples = 10 ms at 16 kHz
  final Float32List frameEnergyDbfs;
  final double noiseFloorDbfs;
  final double speechLevelDbfs;
  final double silenceThresholdDbfs;

  AudioSignal._({
    required this.samples,
    required this.sampleRate,
    required this.frameSize,
    required this.frameEnergyDbfs,
    required this.noiseFloorDbfs,
    required this.speechLevelDbfs,
    required this.silenceThresholdDbfs,
  });

  /// Analyzes the [samples] (assumed 16 kHz mono).
  /// Computes 10 ms frame RMS energy in dBFS, noise floor (P15),
  /// active speech level (P80), and an adaptive silence threshold.
  factory AudioSignal.analyze(
    Float32List samples, {
    int sampleRate = 16000,
    int frameSizeMs = 10,
  }) {
    final frameSize = (sampleRate * frameSizeMs) ~/ 1000;
    final numFrames = samples.length ~/ frameSize;

    if (numFrames == 0) {
      return AudioSignal._(
        samples: samples,
        sampleRate: sampleRate,
        frameSize: frameSize,
        frameEnergyDbfs: Float32List(0),
        noiseFloorDbfs: -60.0,
        speechLevelDbfs: -20.0,
        silenceThresholdDbfs: -45.0,
      );
    }

    final energies = Float32List(numFrames);
    const double epsilon = 1e-7;

    for (int f = 0; f < numFrames; f++) {
      final start = f * frameSize;
      double sumSquares = 0.0;
      for (int i = 0; i < frameSize; i++) {
        final s = samples[start + i];
        sumSquares += s * s;
      }
      final rms = math.sqrt(sumSquares / frameSize);
      // Convert to dBFS (0 dBFS is full-scale sine/square amplitude ~ 1.0)
      final dbfs = 20.0 * (math.log(rms + epsilon) / math.ln10);
      energies[f] = dbfs.clamp(-100.0, 0.0);
    }

    // Sort a copy to compute empirical percentiles
    final sorted = Float32List.fromList(energies)..sort();
    final p15Index = ((numFrames - 1) * 0.15).round();
    final p80Index = ((numFrames - 1) * 0.80).round();

    final noiseFloor = sorted[p15Index];
    final speechLevel = sorted[p80Index];

    // Adaptive threshold per P2.0 specification:
    // T = clamp(max(speechLevel - 24 dB, noiseFloor + 8 dB), -62 dBFS, -36 dBFS)
    final candidate = math.max(speechLevel - 24.0, noiseFloor + 8.0);
    final silenceThreshold = candidate.clamp(-62.0, -36.0);

    return AudioSignal._(
      samples: samples,
      sampleRate: sampleRate,
      frameSize: frameSize,
      frameEnergyDbfs: energies,
      noiseFloorDbfs: noiseFloor,
      speechLevelDbfs: speechLevel,
      silenceThresholdDbfs: silenceThreshold,
    );
  }

  /// Converts a frame index to its timestamp in seconds.
  double frameToSeconds(int frameIndex) =>
      (frameIndex * frameSize) / sampleRate;

  /// Converts a timestamp in seconds to its frame index.
  int secondsToFrame(double seconds) =>
      ((seconds * sampleRate) / frameSize).floor();

  /// Total duration of the analyzed audio in seconds.
  double get totalSeconds => samples.length / sampleRate;
}
