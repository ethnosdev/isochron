import 'dart:math' as math;
import 'ctc_aligner.dart';
import 'mms_tokenizer.dart';
import 'onnx_emissions_engine.dart';

class PlacedVerseTiming {
  final int index;
  final double start;
  final double end;
  final double speechStart;
  final double speechEnd;
  final double meanLogProb;
  final List<String> warnings;
  final List<String> flags;
  final double? confidence;

  const PlacedVerseTiming({
    required this.index,
    required this.start,
    required this.end,
    required this.speechStart,
    required this.speechEnd,
    required this.meanLogProb,
    required this.warnings,
    this.flags = const [],
    this.confidence,
  });
}

class BoundaryPlacer {
  /// Places verse boundaries using the calibrated lead-in rule and contiguous tiling.
  ///
  /// [verseRanges]: token ranges for each verse from MmsTokenizer.
  /// [tokenTimings]: aligned token timings from CtcAligner.
  /// [trackDurationSeconds]: total audio duration in seconds.
  /// [leadInSeconds]: offset subtracted from first-character speech onset (default 0.17s).
  static List<PlacedVerseTiming> placeBoundaries({
    required List<VerseTokenRange> verseRanges,
    required List<TokenTiming> tokenTimings,
    required double trackDurationSeconds,
    double leadInSeconds = 0.17,
  }) {
    final rawResults = <PlacedVerseTiming>[];

    for (final range in verseRanges) {
      if (range.isEmpty) {
        rawResults.add(
          PlacedVerseTiming(
            index: range.verseIndex,
            start: -1.0,
            end: -1.0,
            speechStart: -1.0,
            speechEnd: -1.0,
            meanLogProb: -20.0,
            warnings: List.from(range.warnings),
          ),
        );
        continue;
      }

      // Filter stranded low-confidence prefix tokens separated by an internal gap > 0.5s
      var effectiveStartIdx = range.tokenStartIndex;
      final maxPrefixCheck = math.min(range.tokenStartIndex + 5, range.tokenEndIndex - 1);
      for (var k = range.tokenStartIndex; k < maxPrefixCheck; k++) {
        final curTok = tokenTimings[k];
        final nextTok = tokenTimings[k + 1];
        final gap = nextTok.startTimeSeconds - curTok.endTimeSeconds;
        if (gap > 0.5) {
          var prefixSum = 0.0;
          for (var p = range.tokenStartIndex; p <= k; p++) {
            prefixSum += tokenTimings[p].meanLogProb;
          }
          final prefixAvg = prefixSum / (k - range.tokenStartIndex + 1);
          if (prefixAvg < -4.0) {
            effectiveStartIdx = k + 1;
          }
          break;
        }
      }

      // Filter stranded low-confidence suffix tokens separated by an internal gap > 0.5s
      var effectiveEndIdx = range.tokenEndIndex - 1;
      final minSuffixCheck = math.max(range.tokenStartIndex, range.tokenEndIndex - 6);
      for (var k = range.tokenEndIndex - 1; k > minSuffixCheck; k--) {
        final curTok = tokenTimings[k];
        final prevTok = tokenTimings[k - 1];
        final gap = curTok.startTimeSeconds - prevTok.endTimeSeconds;
        if (gap > 0.5) {
          var suffixSum = 0.0;
          for (var p = k; p < range.tokenEndIndex; p++) {
            suffixSum += tokenTimings[p].meanLogProb;
          }
          final suffixAvg = suffixSum / (range.tokenEndIndex - k);
          if (suffixAvg < -4.0) {
            effectiveEndIdx = k - 1;
          }
          break;
        }
      }

      final firstToken = tokenTimings[effectiveStartIdx];
      final lastToken = tokenTimings[effectiveEndIdx];

      final speechStart = firstToken.startFrame * OnnxEmissionsEngine.frameDurationSeconds;
      final speechEnd = lastToken.endFrame * OnnxEmissionsEngine.frameDurationSeconds;

      var sumLogProb = 0.0;
      for (var k = range.tokenStartIndex; k < range.tokenEndIndex; k++) {
        sumLogProb += tokenTimings[k].meanLogProb;
      }
      final meanLogProb = sumLogProb / range.length;

      final start = math.max(0.0, speechStart - leadInSeconds);

      rawResults.add(
        PlacedVerseTiming(
          index: range.verseIndex,
          start: start,
          end: speechEnd, // preliminary
          speechStart: speechStart,
          speechEnd: speechEnd,
          meanLogProb: meanLogProb,
          warnings: List.from(range.warnings),
        ),
      );
    }

    // Apply contiguous tiling: end(N) = start(N+1), last end = trackDurationSeconds
    final finalResults = <PlacedVerseTiming>[];
    int? lastTimedIndex;

    for (var i = 0; i < rawResults.length; i++) {
      final cur = rawResults[i];
      if (cur.start < 0) {
        finalResults.add(cur);
        continue;
      }

      if (lastTimedIndex == null) {
        // First timed verse
        finalResults.add(cur);
        lastTimedIndex = finalResults.length - 1;
      } else {
        final prev = finalResults[lastTimedIndex];
        // Enforce monotonicity: current start must be >= previous start + min duration (10ms)
        final safeStart = math.max(prev.start + 0.010, cur.start);

        // Update previous verse's end to meet current verse's start
        final updatedPrev = PlacedVerseTiming(
          index: prev.index,
          start: prev.start,
          end: safeStart,
          speechStart: prev.speechStart,
          speechEnd: prev.speechEnd,
          meanLogProb: prev.meanLogProb,
          warnings: prev.warnings,
        );
        finalResults[lastTimedIndex] = updatedPrev;

        final updatedCur = PlacedVerseTiming(
          index: cur.index,
          start: safeStart,
          end: trackDurationSeconds, // preliminary until next timed verse
          speechStart: cur.speechStart,
          speechEnd: cur.speechEnd,
          meanLogProb: cur.meanLogProb,
          warnings: cur.warnings,
        );
        finalResults.add(updatedCur);
        lastTimedIndex = finalResults.length - 1;
      }
    }

    // Ensure the very last timed verse extends to track end
    if (lastTimedIndex != null) {
      final last = finalResults[lastTimedIndex];
      final finalEnd = math.max(last.start + 0.010, trackDurationSeconds);
      finalResults[lastTimedIndex] = PlacedVerseTiming(
        index: last.index,
        start: last.start,
        end: finalEnd,
        speechStart: last.speechStart,
        speechEnd: last.speechEnd,
        meanLogProb: last.meanLogProb,
        warnings: last.warnings,
      );
    }

    return finalResults;
  }
}
