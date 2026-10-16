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

    test('prevents adjacent boundaries from claiming the same pause', () {
      // Pause from 4.0s to 5.0s
      const pauses = [
        AudioPause(
          startSeconds: 4.0,
          endSeconds: 5.0,
          durationSeconds: 1.0,
          minEnergyDbfs: -65.0,
        ),
      ];

      // Two close boundaries: boundary 0 at 4.6s, boundary 1 at 5.2s
      final raw = [4.6, 5.2];
      final snapped = snapper.snapBoundaries(raw, pauses);

      // Boundary 0 claims pause [4.0..5.0] -> 5.0 - 0.19 = 4.81s
      expect(snapped[0], closeTo(4.81, 0.001));
      // Boundary 1 cannot claim the same pause, must stay >= snapped[0] + minVerseDuration
      expect(snapped[1], greaterThanOrEqualTo(snapped[0] + 0.150));
      expect(snapped[1] - snapped[0], greaterThanOrEqualTo(0.150));
    });

    test('does not snap to distant pause when boundary occurs during continuous speech', () {
      // Pause at [10.0 .. 10.38]
      const pauses = [
        AudioPause(
          startSeconds: 10.09,
          endSeconds: 10.38,
          durationSeconds: 0.29,
          minEnergyDbfs: -65.0,
        ),
      ];

      // Boundary 0 at 10.23 (near pause), Boundary 1 at 10.89 (no pause nearby, continuous speech)
      final raw = [10.23, 10.89];
      final snapped = snapper.snapBoundaries(raw, pauses);

      expect(snapped[0], closeTo(10.191, 0.01));
      // Boundary 1 must NOT reach backward to 10.191; it stays near 10.89
      expect(snapped[1], closeTo(10.89, 0.01));
    });
  });
}
