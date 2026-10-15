import 'audio_signal.dart';

/// Represents a detected silence / pause interval in audio.
class AudioPause {
  final double startSeconds;
  final double endSeconds;
  final double durationSeconds;
  final double minEnergyDbfs;

  const AudioPause({
    required this.startSeconds,
    required this.endSeconds,
    required this.durationSeconds,
    required this.minEnergyDbfs,
  });

  bool contains(double timestamp) =>
      timestamp >= startSeconds && timestamp <= endSeconds;

  @override
  String toString() =>
      'AudioPause(${startSeconds.toStringAsFixed(3)}s - ${endSeconds.toStringAsFixed(3)}s, '
      'dur: ${(durationSeconds * 1000).toStringAsFixed(0)}ms, min: ${minEnergyDbfs.toStringAsFixed(1)}dBFS)';
}

/// Detects pause intervals in an [AudioSignal] using adaptive or explicit thresholding.
class PauseDetector {
  final double minDurationSeconds;
  final int onsetConfirmationFrames;

  const PauseDetector({
    this.minDurationSeconds = 0.100, // 100 ms minimum inter-verse pause
    this.onsetConfirmationFrames = 3, // 30 ms debounce
  });

  /// Detects pauses in [signal].
  /// If [thresholdDbfs] is omitted, uses the signal's adaptive [silenceThresholdDbfs].
  List<AudioPause> detectPauses(
    AudioSignal signal, {
    double? thresholdDbfs,
  }) {
    final threshold = thresholdDbfs ?? signal.silenceThresholdDbfs;
    final energies = signal.frameEnergyDbfs;
    final numFrames = energies.length;

    if (numFrames == 0) return [];

    final pauses = <AudioPause>[];
    int? currentStartFrame;
    double currentMinEnergy = 0.0;

    for (int i = 0; i < numFrames; i++) {
      final isBelow = energies[i] < threshold;

      if (isBelow) {
        if (currentStartFrame == null) {
          currentStartFrame = i;
          currentMinEnergy = energies[i];
        } else {
          if (energies[i] < currentMinEnergy) {
            currentMinEnergy = energies[i];
          }
        }
      } else {
        if (currentStartFrame != null) {
          final runFrames = i - currentStartFrame;
          final durationSec = signal.frameToSeconds(runFrames);

          if (runFrames >= onsetConfirmationFrames &&
              durationSec >= minDurationSeconds) {
            pauses.add(AudioPause(
              startSeconds: signal.frameToSeconds(currentStartFrame),
              endSeconds: signal.frameToSeconds(i),
              durationSeconds: durationSec,
              minEnergyDbfs: currentMinEnergy,
            ));
          }
          currentStartFrame = null;
        }
      }
    }

    // Handle trailing pause at end of file
    if (currentStartFrame != null) {
      final runFrames = numFrames - currentStartFrame;
      final durationSec = signal.frameToSeconds(runFrames);
      if (runFrames >= onsetConfirmationFrames &&
          durationSec >= minDurationSeconds) {
        pauses.add(AudioPause(
          startSeconds: signal.frameToSeconds(currentStartFrame),
          endSeconds: signal.totalSeconds,
          durationSeconds: durationSec,
          minEnergyDbfs: currentMinEnergy,
        ));
      }
    }

    return pauses;
  }
}
