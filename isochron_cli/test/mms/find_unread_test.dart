import 'package:test/test.dart';
import 'package:isochron_cli/src/audio/pause_detector.dart';
import 'package:isochron_cli/src/core/fragment.dart';
import 'package:isochron_cli/src/mms/boundary_placer.dart';
import 'package:isochron_cli/src/mms/find_unread.dart';

void main() {
  group('UnreadDetector (Omission Detection)', () {
    const detector = UnreadDetector(maxCharsPerSecond: 25.0, minLogProb: -4.5);

    test('retains normally read verses without modification', () {
      final frags = [
        Fragment(index: 0, text: 'In the beginning God created the heaven and the earth.'),
        Fragment(index: 1, text: 'And the earth was without form, and void.'),
      ];
      final timings = [
        const PlacedVerseTiming(
          index: 0,
          start: 0.0,
          end: 4.0,
          speechStart: 0.2,
          speechEnd: 3.8,
          meanLogProb: -1.2,
          warnings: [],
        ),
        const PlacedVerseTiming(
          index: 1,
          start: 4.0,
          end: 8.0,
          speechStart: 4.2,
          speechEnd: 7.7,
          meanLogProb: -1.5,
          warnings: [],
        ),
      ];

      final result = detector.detectOmissions(
        timings: timings,
        fragments: frags,
        trackDurationSeconds: 8.0,
      );

      expect(result.length, 2);
      expect(result[0].start, 0.0);
      expect(result[0].end, 4.0);
      expect(result[0].flags, isEmpty);
      expect(result[1].start, 4.0);
      expect(result[1].end, 8.0);
      expect(result[1].flags, isEmpty);
    });

    test('identifies skipped verse and re-stitches surrounding boundaries', () {
      final frags = [
        Fragment(index: 0, text: 'First verse that was spoken normally.'),
        Fragment(index: 1, text: 'This entire second verse was completely skipped by the narrator.'),
        Fragment(index: 2, text: 'Third verse spoken normally after the skipped one.'),
      ];
      final timings = [
        const PlacedVerseTiming(
          index: 0,
          start: 0.0,
          end: 3.5,
          speechStart: 0.2,
          speechEnd: 3.4,
          meanLogProb: -1.0,
          warnings: [],
        ),
        // Compressed into 0.04s with terrible log-prob -> omitted!
        const PlacedVerseTiming(
          index: 1,
          start: 3.5,
          end: 3.54,
          speechStart: 3.5,
          speechEnd: 3.54,
          meanLogProb: -5.8,
          warnings: [],
        ),
        const PlacedVerseTiming(
          index: 2,
          start: 3.54,
          end: 7.0,
          speechStart: 3.8,
          speechEnd: 6.9,
          meanLogProb: -0.9,
          warnings: [],
        ),
      ];

      final result = detector.detectOmissions(
        timings: timings,
        fragments: frags,
        trackDurationSeconds: 7.0,
      );

      expect(result.length, 3);

      // Verse 1 is omitted
      expect(result[1].start, -1.0);
      expect(result[1].end, -1.0);
      expect(result[1].flags, contains('omitted'));
      expect(result[1].confidence, 0.0);

      // Verse 0 end should now connect directly to Verse 2 start
      expect(result[0].start, 0.0);
      expect(result[0].end, result[2].start);
      expect(result[2].end, 7.0);
    });

    test('handles omission of the first verse', () {
      final frags = [
        Fragment(index: 0, text: 'Skipped title or first introductory verse.'),
        Fragment(index: 1, text: 'Actual spoken first line of audio track.'),
      ];
      final timings = [
        const PlacedVerseTiming(
          index: 0,
          start: 0.0,
          end: 0.02,
          speechStart: 0.0,
          speechEnd: 0.02,
          meanLogProb: -6.0,
          warnings: [],
        ),
        const PlacedVerseTiming(
          index: 1,
          start: 0.02,
          end: 5.0,
          speechStart: 0.5,
          speechEnd: 4.8,
          meanLogProb: -1.1,
          warnings: [],
        ),
      ];

      final result = detector.detectOmissions(
        timings: timings,
        fragments: frags,
        trackDurationSeconds: 5.0,
      );

      expect(result[0].start, -1.0);
      expect(result[0].flags, contains('omitted'));
      expect(result[1].start, 0.02);
      expect(result[1].end, 5.0);
    });

    test('re-anchors first timed verse to preceding pause when first verse is omitted', () {
      final frags = [
        Fragment(index: 0, text: 'Skipped title or first introductory verse.'),
        Fragment(index: 1, text: 'Actual spoken first line of audio track.'),
      ];
      final timings = [
        const PlacedVerseTiming(
          index: 0,
          start: 0.0,
          end: 0.5,
          speechStart: 0.2,
          speechEnd: 0.4,
          meanLogProb: -6.0,
          warnings: [],
        ),
        const PlacedVerseTiming(
          index: 1,
          start: 0.5,
          end: 8.0,
          speechStart: 4.0,
          speechEnd: 7.8,
          meanLogProb: -1.1,
          warnings: [],
        ),
      ];
      const pauses = [
        AudioPause(
          startSeconds: 1.0,
          endSeconds: 3.9,
          durationSeconds: 2.9,
          minEnergyDbfs: -65.0,
        ),
      ];

      final result = detector.detectOmissions(
        timings: timings,
        fragments: frags,
        trackDurationSeconds: 8.0,
        pauses: pauses,
        leadInSeconds: 0.19,
      );

      expect(result[0].start, -1.0);
      // Re-anchored to pause: 3.9 - 0.19 = 3.71s
      expect(result[1].start, closeTo(3.71, 0.01));
      expect(result[1].end, 8.0);
    });

    test('handles omission of the last verse', () {
      final frags = [
        Fragment(index: 0, text: 'Spoken verse.'),
        Fragment(index: 1, text: 'Skipped concluding verse.'),
      ];
      final timings = [
        const PlacedVerseTiming(
          index: 0,
          start: 0.0,
          end: 4.95,
          speechStart: 0.2,
          speechEnd: 4.8,
          meanLogProb: -1.0,
          warnings: [],
        ),
        const PlacedVerseTiming(
          index: 1,
          start: 4.95,
          end: 5.0,
          speechStart: 4.96,
          speechEnd: 4.98,
          meanLogProb: -5.5,
          warnings: [],
        ),
      ];

      final result = detector.detectOmissions(
        timings: timings,
        fragments: frags,
        trackDurationSeconds: 5.0,
      );

      expect(result[0].start, 0.0);
      expect(result[0].end, 5.0); // Extended to track end
      expect(result[1].start, -1.0);
      expect(result[1].flags, contains('omitted'));
    });
  });
}
