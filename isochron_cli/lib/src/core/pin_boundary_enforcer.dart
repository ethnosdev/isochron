import 'fragment.dart';

/// Applies a post-processing pass to ensure fragment timings respect pin
/// boundaries with no gaps or overlaps.
///
/// This runs after [BoundarySnapper] because the energy-onset snapper can
/// advance a fragment's start past a pin boundary (creating a gap) or DTW
/// can land a fragment slightly inside an adjacent pin's window (creating an
/// overlap).
///
/// **Forward pass (left → right):**
/// - If fragment[i-1] is pinned, fragment[i].realStart is set to
///   fragment[i-1].realEnd (eliminates the gap that snapping can introduce
///   after a pin).
/// - If fragment[i].realStart < fragment[i-1].realEnd (any overlap with the
///   previous fragment), fragment[i].realStart is advanced to fix it.
///
/// **Backward pass (right → left):**
/// - If fragment[i+1] is pinned, fragment[i].realEnd is set to
///   fragment[i+1].realStart (eliminates overlaps that DTW can create before
///   a pin).
/// - If fragment[i].realEnd > fragment[i+1].realStart (any overlap into the
///   next fragment), fragment[i].realEnd is pulled back to fix it.
///
/// Pinned fragments themselves are never moved.
class PinBoundaryEnforcer {
  /// Enforce pin boundaries on [fragments] in-place.
  ///
  /// Assumes [fragments] are in ascending index order and already have
  /// [Fragment.realStart] / [Fragment.realEnd] set for every fragment.
  static void enforce(List<Fragment> fragments) {
    if (fragments.length < 2) return;

    // ── Forward pass ─────────────────────────────────────────────────────────
    // After a pinned fragment: always chain the next fragment's start to the
    // pin's end (no gap). For non-pinned→non-pinned: only fix actual overlaps.
    for (int i = 1; i < fragments.length; i++) {
      if (fragments[i].isPinned) continue;
      final prevEnd = fragments[i - 1].realEnd;
      if (fragments[i - 1].isPinned || fragments[i].realStart < prevEnd) {
        fragments[i].realStart = prevEnd;
      }
    }

    // ── Backward pass ─────────────────────────────────────────────────────────
    // Before a pinned fragment: always chain the previous fragment's end to the
    // pin's start (no gap or overlap). For non-pinned→non-pinned: only fix
    // actual overlaps.
    for (int i = fragments.length - 2; i >= 0; i--) {
      if (fragments[i].isPinned) continue;
      final nextStart = fragments[i + 1].realStart;
      if (fragments[i + 1].isPinned || fragments[i].realEnd > nextStart) {
        fragments[i].realEnd = nextStart;
      }

      // Guard: realEnd must never be less than realStart (possible when a
      // very narrow window is squeezed between two close pins).
      if (fragments[i].realEnd < fragments[i].realStart) {
        fragments[i].realEnd = fragments[i].realStart;
      }
    }
  }
}
