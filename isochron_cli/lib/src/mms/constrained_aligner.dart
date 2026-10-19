import 'dart:math' as math;
import '../audio/pause_detector.dart';
import '../core/fragment.dart';
import 'boundary_placer.dart';
import 'ctc_aligner.dart';
import 'mms_pipeline.dart';
import 'mms_tokenizer.dart';
import 'onnx_emissions_engine.dart';
import 'pause_snapper.dart';

/// Segment representing a group of fragments between fixed anchors.
class _AlignmentSpan {
  final int startFragIndex;
  final int endFragIndex; // inclusive
  final double startTime;
  final double endTime;
  final bool isFixed;

  _AlignmentSpan({
    required this.startFragIndex,
    required this.endFragIndex,
    required this.startTime,
    required this.endTime,
    required this.isFixed,
  });

  int get length => endFragIndex - startFragIndex + 1;
}

/// Aligns fragments while strictly preserving user-edited and reviewed boundaries
/// as hard constraints. The CTC trellis is solved independently within each interval
/// between fixed anchors.
class ConstrainedAligner {
  final MmsTokenizer tokenizer;

  const ConstrainedAligner({required this.tokenizer});

  /// Identifies fixed anchors from fragments with status `edited` or `reviewed`.
  /// Partitions the track into independent spans and aligns each unlocked span.
  List<PlacedVerseTiming> alignConstrained({
    required List<Fragment> fragments,
    required EmissionsOutput emissions,
    required List<AudioPause> pauses,
    required double trackDurationSeconds,
    required MmsPipelineOptions options,
    void Function(String status, double progress)? onProgress,
  }) {
    if (fragments.isEmpty) return [];

    final spans = _partitionSpans(fragments, trackDurationSeconds);
    final allTimings = <PlacedVerseTiming>[];

    for (int s = 0; s < spans.length; s++) {
      final span = spans[s];
      final spanFragments = fragments.sublist(
        span.startFragIndex,
        span.endFragIndex + 1,
      );

      if (span.isFixed) {
        // All fragments in this span are fixed by the user
        for (int i = 0; i < spanFragments.length; i++) {
          final f = spanFragments[i];
          final origIndex = span.startFragIndex + i;
          allTimings.add(PlacedVerseTiming(
            index: origIndex,
            start: f.realStart,
            end: f.realEnd,
            speechStart: f.realStart,
            speechEnd: f.realEnd,
            meanLogProb: 0.0,
            warnings: f.warnings,
            flags: f.flags,
            confidence: f.confidence ?? 1.0,
          ));
        }
        continue;
      }

      // Span contains automatic verses needing alignment within [span.startTime, span.endTime]
      final spanDuration = math.max(0.010, span.endTime - span.startTime);
      final spanStartFrame = (span.startTime /
              OnnxEmissionsEngine.frameDurationSeconds)
          .round()
          .clamp(0, emissions.totalFrames);
      final spanEndFrame = (span.endTime /
              OnnxEmissionsEngine.frameDurationSeconds)
          .round()
          .clamp(spanStartFrame, emissions.totalFrames);

      final subEmissions =
          emissions.subEmissions(spanStartFrame, spanEndFrame);

      final verseTexts = spanFragments.map((f) => f.text).toList();
      final tokenOutput = tokenizer.tokenizeVerses(
        verseTexts,
        languageCode: options.languageCode,
        starPlacement: options.starPlacement,
      );

      // Check if subEmissions has sufficient frames for tokenOutput
      List<PlacedVerseTiming> spanBoundaries;
      if (subEmissions.totalFrames >= tokenOutput.tokenIds.length &&
          tokenOutput.tokenIds.isNotEmpty) {
        try {
          final alignmentResult = CtcAligner.align(
            emissions: subEmissions,
            targetTokenIds: tokenOutput.tokenIds,
            targetTokenChars: tokenOutput.tokenChars,
            leadStarScore: span.startFragIndex == 0
                ? options.leadStarScore
                : options.starScore,
          );

          spanBoundaries = BoundaryPlacer.placeBoundaries(
            verseRanges: tokenOutput.verseRanges,
            tokenTimings: alignmentResult.tokenTimings,
            trackDurationSeconds: spanDuration,
            leadInSeconds: options.leadInSeconds,
          );
        } catch (_) {
          // Fallback to proportional division if CTC fails on constrained edge
          spanBoundaries = _proportionalPlacement(
            spanFragments,
            spanDuration,
            span.startFragIndex,
          );
        }
      } else {
        spanBoundaries = _proportionalPlacement(
          spanFragments,
          spanDuration,
          span.startFragIndex,
        );
      }

      // Shift span boundaries by span.startTime
      final shiftedBoundaries = <PlacedVerseTiming>[];
      for (int i = 0; i < spanBoundaries.length; i++) {
        final b = spanBoundaries[i];
        final actualIndex = span.startFragIndex + i;

        // If the very first fragment of the span was an edited boundary, preserve its start
        final origFrag = spanFragments[i];
        final bool isFirstOfSpan = (i == 0);
        final bool isLastOfSpan = (i == spanBoundaries.length - 1);

        final adjustedStart = (isFirstOfSpan && origFrag.isUserLocked)
            ? origFrag.realStart
            : (span.startTime + b.start)
                .clamp(span.startTime, span.endTime);

        final adjustedEnd = isLastOfSpan
            ? span.endTime
            : (span.startTime + b.end).clamp(adjustedStart, span.endTime);

        shiftedBoundaries.add(PlacedVerseTiming(
          index: actualIndex,
          start: adjustedStart,
          end: adjustedEnd,
          speechStart: span.startTime + b.speechStart,
          speechEnd: span.startTime + b.speechEnd,
          meanLogProb: b.meanLogProb,
          warnings: b.warnings,
          flags: b.flags,
          confidence: b.confidence,
        ));
      }

      // Snapping to pauses within span (for unlocked boundaries)
      if (options.snapToPauses && pauses.isNotEmpty) {
        final spanPauses = pauses
            .where((p) =>
                p.endSeconds >= span.startTime &&
                p.startSeconds <= span.endTime)
            .toList();

        if (spanPauses.isNotEmpty) {
          final snapper = PauseSnapper(
            searchWindowSeconds: options.pauseSearchWindowSeconds,
            leadInSeconds: options.leadInSeconds,
          );
          final rawStarts = shiftedBoundaries.map((b) => b.start).toList();
          final snappedStarts =
              snapper.snapBoundaries(rawStarts, spanPauses);

          for (int i = 0; i < shiftedBoundaries.length; i++) {
            final orig = shiftedBoundaries[i];
            final frag = spanFragments[i];
            if (frag.isUserLocked) continue; // Keep user boundary locked

            final newStart = snappedStarts[i].clamp(
              span.startTime,
              span.endTime,
            );
            final newEnd = (i + 1 < shiftedBoundaries.length)
                ? snappedStarts[i + 1].clamp(newStart, span.endTime)
                : span.endTime;

            shiftedBoundaries[i] = PlacedVerseTiming(
              index: orig.index,
              start: newStart,
              end: newEnd,
              speechStart: orig.speechStart,
              speechEnd: orig.speechEnd,
              meanLogProb: orig.meanLogProb,
              warnings: orig.warnings,
              flags: orig.flags,
              confidence: orig.confidence,
            );
          }
        }
      }

      allTimings.addAll(shiftedBoundaries);
    }

    return allTimings;
  }

  static List<_AlignmentSpan> _partitionSpans(
    List<Fragment> fragments,
    double trackDurationSeconds,
  ) {
    final spans = <_AlignmentSpan>[];
    int currentSpanStart = 0;

    for (int i = 1; i < fragments.length; i++) {
      if (fragments[i].isUserLocked) {
        // Verse i has a locked start boundary
        final startTime = (currentSpanStart == 0 &&
                !fragments[0].isUserLocked)
            ? 0.0
            : fragments[currentSpanStart].realStart;
        final endTime = fragments[i].realStart;

        spans.add(_AlignmentSpan(
          startFragIndex: currentSpanStart,
          endFragIndex: i - 1,
          startTime: startTime,
          endTime: endTime,
          isFixed: _allLocked(fragments, currentSpanStart, i - 1),
        ));
        currentSpanStart = i;
      }
    }

    // Final span to end of track
    final lastStartTime = (currentSpanStart == 0 &&
            !fragments[0].isUserLocked)
        ? 0.0
        : fragments[currentSpanStart].realStart;
    spans.add(_AlignmentSpan(
      startFragIndex: currentSpanStart,
      endFragIndex: fragments.length - 1,
      startTime: lastStartTime,
      endTime: trackDurationSeconds,
      isFixed:
          _allLocked(fragments, currentSpanStart, fragments.length - 1),
    ));

    return spans;
  }

  static bool _allLocked(List<Fragment> fragments, int start, int end) {
    for (int i = start; i <= end; i++) {
      if (!fragments[i].isUserLocked) return false;
    }
    return true;
  }

  static List<PlacedVerseTiming> _proportionalPlacement(
    List<Fragment> frags,
    double spanDuration,
    int startIndexOffset,
  ) {
    final totalChars = frags.fold<int>(
      0,
      (sum, f) => sum + math.max(1, f.text.trim().length),
    );
    final results = <PlacedVerseTiming>[];
    double curStart = 0.0;

    for (int i = 0; i < frags.length; i++) {
      final f = frags[i];
      final chars = math.max(1, f.text.trim().length);
      final dur = spanDuration * (chars / totalChars);
      final curEnd = (i == frags.length - 1)
          ? spanDuration
          : (curStart + dur);

      results.add(PlacedVerseTiming(
        index: startIndexOffset + i,
        start: curStart,
        end: curEnd,
        speechStart: curStart,
        speechEnd: curEnd,
        meanLogProb: -1.0,
        warnings: const [],
      ));
      curStart = curEnd;
    }
    return results;
  }
}

extension on Fragment {
  bool get isUserLocked =>
      status == FragmentStatus.edited || status == FragmentStatus.reviewed;
}
