import 'dart:math' as math;
import '../audio/pause_detector.dart';
import '../core/fragment.dart';
import 'boundary_placer.dart';

/// Analyzes verse timings, acoustic emissions quality, and pauses to generate
/// calibrated confidence scores and diagnostic anomaly flags.
class QualityAnalyzer {
  static const double minLogProbForGoodMatch = -4.0;
  static const double pauseProximityThresholdSeconds = 0.15;
  static const double minReadingRateCharsPerSec = 5.0;
  static const double maxReadingRateCharsPerSec = 22.0;

  /// Analyzes verse timings and fragments to attach diagnostic flags and confidence scores.
  static List<PlacedVerseTiming> analyze({
    required List<PlacedVerseTiming> timings,
    required List<Fragment> fragments,
    required List<AudioPause> pauses,
  }) {
    final results = <PlacedVerseTiming>[];

    for (int i = 0; i < timings.length; i++) {
      final t = timings[i];
      final f = fragments[i];
      final cleanText = f.text.trim();
      final flags = List<String>.from(t.flags);

      if (t.start < 0) {
        // Untimed or omitted verse
        results.add(PlacedVerseTiming(
          index: t.index,
          start: t.start,
          end: t.end,
          speechStart: t.speechStart,
          speechEnd: t.speechEnd,
          meanLogProb: t.meanLogProb,
          warnings: t.warnings,
          flags: flags,
          confidence: 0.0,
        ));
        continue;
      }

      final duration = t.end - t.start;
      final speechDuration = t.speechEnd - t.speechStart;
      final effectiveSpeechDur =
          speechDuration > 0 ? speechDuration : duration;
      final readingRate = cleanText.isNotEmpty
          ? cleanText.length /
              (effectiveSpeechDur > 0 ? effectiveSpeechDur : 0.001)
          : 0.0;

      // 1. poor_text_match
      if (t.meanLogProb < minLogProbForGoodMatch) {
        if (!flags.contains('poor_text_match')) {
          flags.add('poor_text_match');
        }
      }

      // 2. not_at_pause (for verses after the first)
      double minPauseDist = double.infinity;
      if (pauses.isNotEmpty) {
        for (final p in pauses) {
          if (t.start >= p.startSeconds && t.start <= p.endSeconds) {
            minPauseDist = 0.0;
            break;
          }
          final dist = math.min(
            (t.start - p.startSeconds).abs(),
            (t.start - p.endSeconds).abs(),
          );
          if (dist < minPauseDist) minPauseDist = dist;
        }
      }

      if (i > 0 && minPauseDist > pauseProximityThresholdSeconds) {
        if (!flags.contains('not_at_pause')) {
          flags.add('not_at_pause');
        }
      }

      // 3. long_verse / short_verse
      if (cleanText.isNotEmpty) {
        if (duration > 10.0 && readingRate < minReadingRateCharsPerSec) {
          if (!flags.contains('long_verse')) {
            flags.add('long_verse');
          }
        } else if (readingRate > maxReadingRateCharsPerSec ||
            (duration < 0.5 && cleanText.length > 10)) {
          if (!flags.contains('short_verse')) {
            flags.add('short_verse');
          }
        }
      }

      // 4. Confidence scoring [0.0, 1.0]
      final cAcoustic =
          ((t.meanLogProb + 4.5) / 4.0).clamp(0.0, 1.0);
      double cPause = 1.0;
      if (i > 0) {
        if (minPauseDist <= 0.10) {
          cPause = 1.0;
        } else if (minPauseDist <= 0.25) {
          cPause = 0.8;
        } else {
          cPause = 0.5;
        }
      }

      var conf = 0.70 * cAcoustic + 0.30 * cPause;
      if (flags.contains('poor_text_match')) conf *= 0.70;
      if (flags.contains('long_verse') || flags.contains('short_verse')) {
        conf *= 0.85;
      }
      if (flags.contains('not_at_pause')) conf *= 0.90;

      final roundedConf =
          double.parse(conf.clamp(0.0, 1.0).toStringAsFixed(2));

      results.add(PlacedVerseTiming(
        index: t.index,
        start: t.start,
        end: t.end,
        speechStart: t.speechStart,
        speechEnd: t.speechEnd,
        meanLogProb: t.meanLogProb,
        warnings: t.warnings,
        flags: flags,
        confidence: roundedConf,
      ));
    }

    return results;
  }
}
