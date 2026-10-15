import '../core/fragment.dart';
import 'boundary_placer.dart';

/// Identifies unread or skipped verses where audio duration is physically
/// insufficient (> 25 chars/second) and average character emission log-probability
/// drops below -4.5.
///
/// Sets timestamps of omitted verses to -1.0 and marks them with the 'omitted' flag.
/// Re-tiles adjacent non-omitted verses to maintain contiguous boundary continuity.
class UnreadDetector {
  final double maxCharsPerSecond;
  final double minLogProb;

  const UnreadDetector({
    this.maxCharsPerSecond = 25.0,
    this.minLogProb = -4.5,
  });

  List<PlacedVerseTiming> detectOmissions({
    required List<PlacedVerseTiming> timings,
    required List<Fragment> fragments,
    required double trackDurationSeconds,
  }) {
    if (timings.isEmpty) return [];

    final intermediate = <PlacedVerseTiming>[];
    final omittedIndices = <int>{};

    for (int i = 0; i < timings.length; i++) {
      final t = timings[i];
      final f = fragments[i];
      final cleanText = f.text.trim();

      // If already untimed, preserve
      if (t.start < 0) {
        intermediate.add(t);
        continue;
      }

      final speechDur = t.speechEnd - t.speechStart;
      final charsPerSec = cleanText.isNotEmpty
          ? cleanText.length / (speechDur > 0 ? speechDur : 0.001)
          : 0.0;

      final isOmitted = cleanText.isNotEmpty &&
          (charsPerSec > maxCharsPerSecond ||
              (speechDur < 0.05 && cleanText.length >= 8)) &&
          t.meanLogProb < minLogProb;

      if (isOmitted) {
        omittedIndices.add(i);
        final flags = List<String>.from(t.flags);
        if (!flags.contains('omitted')) flags.add('omitted');
        intermediate.add(PlacedVerseTiming(
          index: t.index,
          start: -1.0,
          end: -1.0,
          speechStart: -1.0,
          speechEnd: -1.0,
          meanLogProb: t.meanLogProb,
          warnings: t.warnings,
          flags: flags,
          confidence: 0.0,
        ));
      } else {
        intermediate.add(t);
      }
    }

    if (omittedIndices.isEmpty) {
      return intermediate;
    }

    // Re-tile non-omitted verses to preserve contiguous boundary continuity
    final reTiled = <PlacedVerseTiming>[];
    int? lastTimedIndex;

    for (int i = 0; i < intermediate.length; i++) {
      final cur = intermediate[i];
      if (cur.start < 0) {
        reTiled.add(cur);
        continue;
      }

      if (lastTimedIndex == null) {
        reTiled.add(cur);
        lastTimedIndex = reTiled.length - 1;
      } else {
        // Stitch previous end to current start
        final prev = reTiled[lastTimedIndex];
        reTiled[lastTimedIndex] = PlacedVerseTiming(
          index: prev.index,
          start: prev.start,
          end: cur.start,
          speechStart: prev.speechStart,
          speechEnd: prev.speechEnd,
          meanLogProb: prev.meanLogProb,
          warnings: prev.warnings,
          flags: prev.flags,
          confidence: prev.confidence,
        );
        reTiled.add(cur);
        lastTimedIndex = reTiled.length - 1;
      }
    }

    if (lastTimedIndex != null) {
      final last = reTiled[lastTimedIndex];
      reTiled[lastTimedIndex] = PlacedVerseTiming(
        index: last.index,
        start: last.start,
        end: trackDurationSeconds,
        speechStart: last.speechStart,
        speechEnd: last.speechEnd,
        meanLogProb: last.meanLogProb,
        warnings: last.warnings,
        flags: last.flags,
        confidence: last.confidence,
      );
    }

    return reTiled;
  }
}
