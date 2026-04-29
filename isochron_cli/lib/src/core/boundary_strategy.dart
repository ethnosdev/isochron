import 'dart:typed_data';

import 'fragment.dart';
import '../math/boundary_snapper.dart';

/// High-level snap behaviour used by the alignment pipeline.
///
/// The snap mode controls how fragment boundaries are refined after DTW time
/// projection. New modes should be added here without changing the rest of the
/// pipeline.
enum SnapMode {
  /// Original behaviour: snap each fragment start toward the first energy
  /// onset near the projected time.
  onset,

  /// Refined behaviour: place fragment boundaries near the center of the
  /// detected silence gap between neighbouring fragments.
  gapCenter,
}

/// Strategy interface for boundary snapping.
///
/// Given a list of [Fragment]s whose [Fragment.realStart] / [Fragment.realEnd]
/// have already been projected into real audio time, a snap strategy can refine
/// those timings using the raw audio samples.
abstract class BoundarySnapStrategy {
  void snap({
    required List<Fragment> fragments,
    required Float64List audio,
    required int sampleRate,
  });
}

/// Default implementation that delegates to [BoundarySnapper].
///
/// Existing comments and behaviour in [BoundarySnapper] are preserved and this
/// strategy acts only as a thin adapter.
class OnsetBoundarySnapStrategy implements BoundarySnapStrategy {
  const OnsetBoundarySnapStrategy();

  @override
  void snap({
    required List<Fragment> fragments,
    required Float64List audio,
    required int sampleRate,
  }) {
    BoundarySnapper.snap(fragments, audio, sampleRate);
  }
}

