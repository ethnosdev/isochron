import 'dart:typed_data';
import 'onnx_emissions_engine.dart';

class TokenTiming {
  final int tokenIndex; // index in target token array
  final int tokenId;
  final String char;
  final int startFrame; // inclusive
  final int endFrame;   // exclusive
  final double meanLogProb;

  const TokenTiming({
    required this.tokenIndex,
    required this.tokenId,
    required this.char,
    required this.startFrame,
    required this.endFrame,
    required this.meanLogProb,
  });

  double get startTimeSeconds => startFrame * OnnxEmissionsEngine.frameDurationSeconds;
  double get endTimeSeconds => endFrame * OnnxEmissionsEngine.frameDurationSeconds;
  double get durationSeconds => endTimeSeconds - startTimeSeconds;
}

class AlignmentResult {
  final List<TokenTiming> tokenTimings;
  final double totalLogProb;

  const AlignmentResult({
    required this.tokenTimings,
    required this.totalLogProb,
  });
}

class CtcAligner {
  static const int maxCellCap = 1500000000; // 1.5 billion cells

  /// Runs CTC Viterbi forced alignment over the blank-interleaved target sequence.
  ///
  /// [emissions]: EmissionsOutput of shape [T, 32].
  /// [targetTokenIds]: List of target token IDs (length L).
  /// [targetTokenChars]: String representations of each token for debugging/timing.
  static AlignmentResult align({
    required EmissionsOutput emissions,
    required List<int> targetTokenIds,
    required List<String> targetTokenChars,
    double? leadStarScore = 0.0,
  }) {
    final tFrames = emissions.totalFrames;
    final lTokens = targetTokenIds.length;

    if (tFrames == 0 || lTokens == 0) {
      return const AlignmentResult(tokenTimings: [], totalLogProb: 0.0);
    }

    final hasLeadStar = targetTokenIds.isNotEmpty && targetTokenIds[0] == 31;

    // Interleave with blank (id 0) -> S = 2L + 1 states
    final numStates = 2 * lTokens + 1;
    final stateTokenIds = Int32List(numStates);
    for (var i = 0; i < lTokens; i++) {
      stateTokenIds[2 * i] = 0; // blank
      stateTokenIds[2 * i + 1] = targetTokenIds[i];
    }
    stateTokenIds[numStates - 1] = 0; // final blank

    final totalCells = tFrames * numStates;
    if (totalCells > maxCellCap) {
      throw ArgumentError(
        'Trellis size ($tFrames frames x $numStates states = $totalCells cells) '
        'exceeds maximum allowed safety limit of $maxCellCap cells.',
      );
    }

    // Allocate 2 rows for Viterbi forward scores
    var prevRow = Float32List(numStates);
    var currRow = Float32List(numStates);

    const negInf = -1e30;
    prevRow.fillRange(0, numStates, negInf);

    // Frame 0 initialization:
    // Can start at blank (state 0) or first token (state 1)
    prevRow[0] = emissions.getLogProb(0, 0);
    if (numStates > 1) {
      prevRow[1] = (hasLeadStar && leadStarScore != null)
          ? leadStarScore
          : emissions.getLogProb(0, stateTokenIds[1]);
    }

    // Backpointers: 0 = stay (s), 1 = advance (s - 1), 2 = skip-blank (s - 2)
    final backpointers = Uint8List(tFrames * numStates);

    // Forward pass
    for (var t = 1; t < tFrames; t++) {
      final tOffset = t * numStates;
      currRow.fillRange(0, numStates, negInf);

      // State 0: blank (can only stay from state 0)
      final score0 = prevRow[0] + emissions.getLogProb(t, 0);
      currRow[0] = score0;
      backpointers[tOffset + 0] = 0;

      // State 1: first token (can stay from state 1, or advance from state 0)
      if (numStates > 1) {
        final emit1 = (hasLeadStar && leadStarScore != null)
            ? leadStarScore
            : emissions.getLogProb(t, stateTokenIds[1]);
        final stayScore = prevRow[1];
        final advanceScore = prevRow[0];
        if (stayScore >= advanceScore) {
          currRow[1] = stayScore + emit1;
          backpointers[tOffset + 1] = 0;
        } else {
          currRow[1] = advanceScore + emit1;
          backpointers[tOffset + 1] = 1;
        }
      }

      // States s >= 2
      for (var s = 2; s < numStates; s++) {
        final emit = emissions.getLogProb(t, stateTokenIds[s]);
        var bestScore = prevRow[s];
        var bestBp = 0; // stay

        final advanceScore = prevRow[s - 1];
        if (advanceScore > bestScore) {
          bestScore = advanceScore;
          bestBp = 1; // from s - 1
        }

        // Skip blank condition:
        // Current state s is a token (odd), and differs from previous token (s - 2)
        if (s.isOdd && stateTokenIds[s] != stateTokenIds[s - 2]) {
          final skipScore = prevRow[s - 2];
          if (skipScore > bestScore) {
            bestScore = skipScore;
            bestBp = 2; // from s - 2
          }
        }

        currRow[s] = bestScore + emit;
        backpointers[tOffset + s] = bestBp;
      }

      // Swap rows
      final temp = prevRow;
      prevRow = currRow;
      currRow = temp;
    }

    // Backtracking
    // Optimal end state at frame T-1: either final blank (numStates - 1) or final token (numStates - 2)
    var bestEndState = numStates - 1;
    var bestFinalScore = prevRow[numStates - 1];
    if (numStates >= 2 && prevRow[numStates - 2] > bestFinalScore) {
      bestEndState = numStates - 2;
      bestFinalScore = prevRow[numStates - 2];
    }

    final statePath = Int32List(tFrames);
    var currentState = bestEndState;
    for (var t = tFrames - 1; t >= 0; t--) {
      statePath[t] = currentState;
      if (t > 0) {
        final bp = backpointers[t * numStates + currentState];
        if (bp == 1) {
          currentState -= 1;
        } else if (bp == 2) {
          currentState -= 2;
        }
      }
    }

    // Extract token timings from statePath
    // Each target token k corresponds to odd state: s = 2 * k + 1
    final tokenTimings = <TokenTiming>[];
    for (var k = 0; k < lTokens; k++) {
      final targetState = 2 * k + 1;
      int firstFrame = -1;
      int lastFrame = -1;
      var sumLogProb = 0.0;
      var frameCount = 0;

      for (var t = 0; t < tFrames; t++) {
        if (statePath[t] == targetState) {
          if (firstFrame == -1) firstFrame = t;
          lastFrame = t;
          final emit = (k == 0 && hasLeadStar && leadStarScore != null)
              ? leadStarScore
              : emissions.getLogProb(t, targetTokenIds[k]);
          sumLogProb += emit;
          frameCount++;
        }
      }

      // If token was collapsed/skipped in trellis path, estimate from neighbours
      if (firstFrame == -1) {
        final fallbackFrame = tokenTimings.isNotEmpty
            ? tokenTimings.last.endFrame
            : 0;
        firstFrame = fallbackFrame;
        lastFrame = fallbackFrame;
        sumLogProb = -20.0;
        frameCount = 1;
      }

      tokenTimings.add(
        TokenTiming(
          tokenIndex: k,
          tokenId: targetTokenIds[k],
          char: targetTokenChars[k],
          startFrame: firstFrame,
          endFrame: lastFrame + 1, // exclusive
          meanLogProb: sumLogProb / frameCount,
        ),
      );
    }

    return AlignmentResult(
      tokenTimings: tokenTimings,
      totalLogProb: bestFinalScore,
    );
  }
}
