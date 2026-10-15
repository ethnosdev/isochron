import 'package:test/test.dart';
import 'package:isochron_cli/src/audio/pause_detector.dart';
import 'package:isochron_cli/src/core/fragment.dart';
import 'package:isochron_cli/src/mms/boundary_placer.dart';
import 'package:isochron_cli/src/mms/quality_analyzer.dart';

void main() {
  group('QualityAnalyzer', () {
    test('assigns high confidence and zero flags to well-aligned verses at pauses', () {
      final frags = [
        Fragment(index: 0, text: 'This is the first verse that was clearly spoken.'),
        Fragment(index: 1, text: 'This is the second verse that was clearly spoken.'),
      ];
      final timings = [
        const PlacedVerseTiming(
          index: 0,
          start: 0.0,
          end: 3.5,
          speechStart: 0.2,
          speechEnd: 3.4,
          meanLogProb: -0.6,
          warnings: [],
        ),
        const PlacedVerseTiming(
          index: 1,
          start: 3.5,
          end: 7.0,
          speechStart: 3.7,
          speechEnd: 6.8,
          meanLogProb: -0.7,
          warnings: [],
        ),
      ];
      final pauses = [
        const AudioPause(
          startSeconds: 3.4,
          endSeconds: 3.7,
          durationSeconds: 0.3,
          minEnergyDbfs: -55.0,
        ),
      ];

      final analyzed = QualityAnalyzer.analyze(
        timings: timings,
        fragments: frags,
        pauses: pauses,
      );

      expect(analyzed[0].flags, isEmpty);
      expect(analyzed[0].confidence, greaterThanOrEqualTo(0.90));

      expect(analyzed[1].flags, isEmpty);
      expect(analyzed[1].confidence, greaterThanOrEqualTo(0.90));
    });

    test('flags poor_text_match when log-prob drops below threshold', () {
      final frags = [
        Fragment(index: 0, text: 'Normal verse text here.'),
      ];
      final timings = [
        const PlacedVerseTiming(
          index: 0,
          start: 0.0,
          end: 3.0,
          speechStart: 0.2,
          speechEnd: 2.8,
          meanLogProb: -4.3, // Poor acoustic fit
          warnings: [],
        ),
      ];

      final analyzed = QualityAnalyzer.analyze(
        timings: timings,
        fragments: frags,
        pauses: [],
      );

      expect(analyzed[0].flags, contains('poor_text_match'));
      expect(analyzed[0].confidence, lessThan(0.50));
    });

    test('flags not_at_pause when boundary falls far from any pause', () {
      final frags = [
        Fragment(index: 0, text: 'First verse.'),
        Fragment(index: 1, text: 'Second verse.'),
      ];
      final timings = [
        const PlacedVerseTiming(
          index: 0,
          start: 0.0,
          end: 4.0,
          speechStart: 0.2,
          speechEnd: 3.9,
          meanLogProb: -1.0,
          warnings: [],
        ),
        const PlacedVerseTiming(
          index: 1,
          start: 4.0,
          end: 8.0,
          speechStart: 4.1,
          speechEnd: 7.8,
          meanLogProb: -1.0,
          warnings: [],
        ),
      ];
      // Only pause is at 2.0s, far from boundary at 4.0s
      final pauses = [
        const AudioPause(
          startSeconds: 1.8,
          endSeconds: 2.2,
          durationSeconds: 0.4,
          minEnergyDbfs: -50.0,
        ),
      ];

      final analyzed = QualityAnalyzer.analyze(
        timings: timings,
        fragments: frags,
        pauses: pauses,
      );

      expect(analyzed[1].flags, contains('not_at_pause'));
    });

    test('flags long_verse when reading rate is abnormally slow', () {
      final frags = [
        Fragment(index: 0, text: 'Very short text.'),
      ];
      // 16 chars over 15 seconds = ~1 char/sec -> long_verse
      final timings = [
        const PlacedVerseTiming(
          index: 0,
          start: 0.0,
          end: 15.0,
          speechStart: 0.5,
          speechEnd: 14.5,
          meanLogProb: -1.2,
          warnings: [],
        ),
      ];

      final analyzed = QualityAnalyzer.analyze(
        timings: timings,
        fragments: frags,
        pauses: [],
      );

      expect(analyzed[0].flags, contains('long_verse'));
    });
  });
}
