import 'package:test/test.dart';
import 'package:isochron_cli/src/audio/pause_detector.dart';
import 'package:isochron_cli/src/mms/pause_snapper.dart';

void main() {
  group('PauseSnapper', () {
    const snapper = PauseSnapper(
      searchWindowSeconds: 1.0,
      leadInSeconds: 0.19,
      maxPauseFraction: 0.65,
    );

    test('snaps CTC boundary inside pause to pauseEnd - leadIn', () {
      // Pause from 4.0s to 5.0s (1.0s long)
      const pauses = [
        AudioPause(
          startSeconds: 4.0,
          endSeconds: 5.0,
          durationSeconds: 1.0,
          minEnergyDbfs: -65.0,
        ),
      ];

      // Raw CTC boundary is estimated at 4.7s (inside the pause)
      final raw = [4.7];
      final snapped = snapper.snapBoundaries(raw, pauses);

      // Expected: 5.0 - 0.19 = 4.81s
      expect(snapped.first, closeTo(4.81, 0.001));
    });

    test('respects maxPauseFraction clamp on short pause', () {
      // Pause from 4.0s to 4.2s (200 ms long)
      // leadIn of 190 ms from 4.2s would be 4.01s (which is 95% into the pause).
      // maxPauseFraction = 0.65 clamps start to 4.0 + (1 - 0.65)*0.2 = 4.0 + 0.07 = 4.07s
      const pauses = [
        AudioPause(
          startSeconds: 4.0,
          endSeconds: 4.2,
          durationSeconds: 0.20,
          minEnergyDbfs: -65.0,
        ),
      ];

      final raw = [4.15];
      final snapped = snapper.snapBoundaries(raw, pauses);

      expect(snapped.first, closeTo(4.07, 0.001));
    });

    test('leaves boundary unchanged when no pause is nearby', () {
      const pauses = [
        AudioPause(
          startSeconds: 10.0,
          endSeconds: 11.0,
          durationSeconds: 1.0,
          minEnergyDbfs: -65.0,
        ),
      ];

      final raw = [2.0]; // Distant from pause
      final snapped = snapper.snapBoundaries(raw, pauses);

      expect(snapped.first, 2.0);
    });

    test('preserves monotonicity when boundaries are close', () {
      const pauses = [
        AudioPause(
          startSeconds: 4.0,
          endSeconds: 5.0,
          durationSeconds: 1.0,
          minEnergyDbfs: -65.0,
        ),
      ];

      final raw = [4.7, 4.75];
      final snapped = snapper.snapBoundaries(raw, pauses);

      expect(snapped[0], lessThanOrEqualTo(snapped[1]));
    });
  });
}
