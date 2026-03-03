import 'package:test/test.dart';
import 'package:isochron_cli/isochron_cli.dart';

/// Helper: build a Fragment with realStart/realEnd already set.
Fragment _frag(int index, double start, double end) {
  return Fragment(index: index, text: 'frag$index')
    ..setRealTiming(start: start, end: end);
}

/// Helper: build a pinned Fragment.
Fragment _pinned(int index, double start, double end) {
  final f = Fragment(index: index, text: 'frag$index')
    ..setAnchorTiming(start: 0, end: 0) // irrelevant for these tests
    ..setRealTiming(start: start, end: end);
  f.setPinnedTiming(start: start, end: end);
  return f;
}

void main() {
  group('PinBoundaryEnforcer', () {
    // ── Exact reproduction of the reported demo bugs ──────────────────────────

    test(
        'gap after a pin: start of next fragment is advanced to pin end '
        '(reproduces fragment 1 starting at 7.216 after pin ending at 7.0)',
        () {
      final frags = [
        _pinned(0, 0.0, 7.0), //  pin: 0.0 – 7.0
        _frag(1, 7.216, 11.99), // BoundarySnapper moved start to 7.216
        _pinned(2, 12.0, 18.1), //  pin: 12.0 – 18.1
      ];

      PinBoundaryEnforcer.enforce(frags);

      // Fragment 1 start must be clamped to pin 0's end.
      expect(frags[1].realStart, closeTo(7.0, 0.001));
      // Fragment 1's end must be clamped to pin 2's start.
      expect(frags[1].realEnd, closeTo(12.0, 0.001));
      // Pins are untouched.
      expect(frags[0].realStart, closeTo(0.0, 0.001));
      expect(frags[0].realEnd, closeTo(7.0, 0.001));
      expect(frags[2].realStart, closeTo(12.0, 0.001));
      expect(frags[2].realEnd, closeTo(18.1, 0.001));
    });

    test(
        'overlap before a pin: end of previous fragment is pulled to pin start '
        '(reproduces fragment 3 starting at 17.999 before pin ending at 18.1)',
        () {
      final frags = [
        _pinned(2, 12.0, 18.1), // pin
        _frag(3, 17.999, 27.95), // DTW landed inside pin 2's range
      ];

      PinBoundaryEnforcer.enforce(frags);

      // Fragment 3 start must be clamped to pin 2's end.
      expect(frags[1].realStart, closeTo(18.1, 0.001));
      // Fragment 3's end is unchanged (nothing to its right).
      expect(frags[1].realEnd, closeTo(27.95, 0.001));
    });

    // ── Properties after enforcement ─────────────────────────────────────────

    test('pinned fragments are never modified', () {
      final frags = [
        _frag(0, 0.0, 3.0),
        _pinned(1, 4.0, 6.0), // gap on left, will be exposed
        _frag(2, 5.5, 9.0), // overlap on right
      ];

      PinBoundaryEnforcer.enforce(frags);

      expect(frags[1].realStart, closeTo(4.0, 0.001));
      expect(frags[1].realEnd, closeTo(6.0, 0.001));
    });

    test('non-pinned overlap (no pins involved) is fixed', () {
      final frags = [
        _frag(0, 0.0, 5.0),
        _frag(1, 4.5, 9.0), // 4.5 < 5.0 → overlap
      ];

      PinBoundaryEnforcer.enforce(frags);

      expect(frags[1].realStart, closeTo(5.0, 0.001));
    });

    test('non-pinned gap (no pins involved) is preserved', () {
      // Gaps between non-pinned fragments are intentional (silence between
      // segments); the enforcer only fills gaps caused by pin boundaries.
      final frags = [
        _frag(0, 0.0, 4.0),
        _frag(1, 4.8, 9.0), // 4.8 > 4.0 → gap, not an overlap
      ];

      PinBoundaryEnforcer.enforce(frags);

      expect(frags[1].realStart, closeTo(4.8, 0.001)); // unchanged
    });

    test('output is monotonically ordered with multiple pins', () {
      final frags = [
        _pinned(0, 0.0, 3.0),
        _frag(1, 3.5, 5.9), // gap after pin 0; gap before pin 2
        _pinned(2, 6.0, 7.0),
        _frag(3, 6.8, 10.0), // overlap with pin 2
        _frag(4, 9.0, 12.0), // overlap with fragment 3 after fix
        _pinned(5, 11.5, 13.0),
      ];

      PinBoundaryEnforcer.enforce(frags);

      // All starts and ends should be in non-decreasing order.
      for (int i = 0; i < frags.length; i++) {
        expect(frags[i].realStart, lessThanOrEqualTo(frags[i].realEnd + 0.0001),
            reason: 'fragment $i: realStart must be <= realEnd');
        if (i > 0) {
          expect(frags[i].realStart,
              greaterThanOrEqualTo(frags[i - 1].realEnd - 0.0001),
              reason:
                  'fragment $i: realStart must be >= previous fragment realEnd');
        }
      }

      // Spot-checks.
      expect(frags[1].realStart, closeTo(3.0, 0.001)); // chained to pin 0 end
      expect(frags[1].realEnd, closeTo(6.0, 0.001)); // chained to pin 2 start
      expect(frags[3].realStart, closeTo(7.0, 0.001)); // chained to pin 2 end
    });

    test(
        'degenerate: window squeezed to zero by adjacent pins never inverts '
        'realStart / realEnd', () {
      // Pin 0 ends at 5.0, pin 1 starts at 5.0 — zero-width window.
      final frags = [
        _pinned(0, 0.0, 5.0),
        _frag(1, 4.8, 5.2), // squeezed between two pins
        _pinned(2, 5.0, 8.0),
      ];

      PinBoundaryEnforcer.enforce(frags);

      // Neither realStart nor realEnd should exceed the other.
      expect(frags[1].realStart, lessThanOrEqualTo(frags[1].realEnd + 0.0001));
    });

    test('single fragment list is a no-op', () {
      final frags = [_frag(0, 1.0, 3.0)];
      PinBoundaryEnforcer.enforce(frags);
      expect(frags[0].realStart, closeTo(1.0, 0.001));
      expect(frags[0].realEnd, closeTo(3.0, 0.001));
    });

    test('empty list does not throw', () {
      expect(() => PinBoundaryEnforcer.enforce([]), returnsNormally);
    });

    test('already-correct timings are unchanged', () {
      final frags = [
        _pinned(0, 0.0, 2.0),
        _frag(1, 2.0, 5.0), // already starts exactly at pin end
        _pinned(2, 5.0, 7.0),
      ];

      PinBoundaryEnforcer.enforce(frags);

      expect(frags[1].realStart, closeTo(2.0, 0.001));
      expect(frags[1].realEnd, closeTo(5.0, 0.001));
    });
  });

  // ── Fragment pinning API tests ─────────────────────────────────────────────

  group('Fragment.isPinned', () {
    test('false by default', () {
      expect(Fragment(index: 0, text: 'x').isPinned, isFalse);
    });

    test('true after setPinnedTiming', () {
      final f = Fragment(index: 0, text: 'x');
      f.setPinnedTiming(start: 1.0, end: 2.0);
      expect(f.isPinned, isTrue);
      expect(f.pinnedStart, closeTo(1.0, 0.001));
      expect(f.pinnedEnd, closeTo(2.0, 0.001));
    });

    test('setPinnedTiming does not affect realStart/realEnd', () {
      final f = Fragment(index: 0, text: 'x')
        ..setRealTiming(start: 3.0, end: 4.0);
      f.setPinnedTiming(start: 1.0, end: 2.0);
      // realStart/realEnd are controlled by the processor, not setPinnedTiming
      expect(f.realStart, closeTo(3.0, 0.001));
      expect(f.realEnd, closeTo(4.0, 0.001));
    });
  });
}
