import 'dart:math' as math;
import 'dart:typed_data';
import '../ort/ort_session.dart';

class EmissionsOutput {
  /// 2D matrix of shape [totalFrames, 32] flattened as Float32List.
  /// Index (t, c) = data[t * 32 + c].
  final Float32List data;
  final int totalFrames;
  static const int numClasses = 32; // 31 tokens + 1 star wildcard

  const EmissionsOutput({
    required this.data,
    required this.totalFrames,
  });

  double getLogProb(int frame, int classIndex) =>
      data[frame * numClasses + classIndex];

  /// Extracts a contiguous sub-slice of emissions frames [startFrame, endFrame).
  EmissionsOutput subEmissions(int startFrame, int endFrame) {
    final clampedStart = startFrame.clamp(0, totalFrames);
    final clampedEnd = endFrame.clamp(clampedStart, totalFrames);
    final frameCount = clampedEnd - clampedStart;
    final subData = Float32List.sublistView(
      data,
      clampedStart * numClasses,
      clampedEnd * numClasses,
    );
    return EmissionsOutput(data: subData, totalFrames: frameCount);
  }
}

class OnnxEmissionsEngine {
  final OrtSession session;

  static const int sampleRate = 16000;
  static const int convStride = 320; // 20ms per frame
  static const double frameDurationSeconds = convStride / sampleRate; // 0.02s

  const OnnxEmissionsEngine({required this.session});

  /// Extracts log-probabilities over 32 classes for the entire audio.
  ///
  /// [audio]: 16kHz float32 samples.
  /// [windowSeconds]: Duration of chunk processed at once (default 30s).
  /// [contextSeconds]: Overlap padding on each side (default 2s).
  /// [starScore]: Log-probability assigned to the '*' wildcard column (default 0.0).
  EmissionsOutput computeEmissions(
    Float32List audio, {
    double windowSeconds = 30.0,
    double contextSeconds = 2.0,
    double starScore = 0.0,
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) {
    if (audio.isEmpty) {
      return EmissionsOutput(data: Float32List(0), totalFrames: 0);
    }

    final windowSamples = (windowSeconds * sampleRate).round();
    final contextSamples = (contextSeconds * sampleRate).round();

    final totalAudioSamples = audio.length;
    final totalWindows = (totalAudioSamples / windowSamples).ceil();

    final allFrames = <Float32List>[];

    for (var w = 0; w < totalWindows; w++) {
      if (isCancelled?.call() == true) {
        throw Exception('Inference cancelled');
      }

      final winStart = w * windowSamples;
      final winEnd = math.min(winStart + windowSamples, totalAudioSamples);

      // Context bounds
      final ctxStart = math.max(0, winStart - contextSamples);
      final ctxEnd = math.min(totalAudioSamples, winEnd + contextSamples);

      final chunkLength = ctxEnd - ctxStart;
      if (chunkLength < convStride) continue;

      // 1. Slice and Zero-Mean / Unit-Variance Normalization
      final chunk = Float32List(chunkLength);
      var sum = 0.0;
      for (var i = 0; i < chunkLength; i++) {
        final val = audio[ctxStart + i];
        chunk[i] = val;
        sum += val;
      }
      final mean = sum / chunkLength;

      var sumSqDiff = 0.0;
      for (var i = 0; i < chunkLength; i++) {
        final diff = chunk[i] - mean;
        sumSqDiff += diff * diff;
      }
      final std = math.sqrt(sumSqDiff / chunkLength + 1e-7);
      for (var i = 0; i < chunkLength; i++) {
        chunk[i] = (chunk[i] - mean) / std;
      }

      // 2. Run ONNX Inference
      final inputs = {
        'input_values': (shape: [1, chunkLength], data: chunk),
      };
      final outputs = session.run(inputs);
      final logits = outputs['logits']!;
      // Shape: [1, T, 31]
      final chunkFrames = logits.shape[1];
      final chunkData = logits.data;

      // 3. Compute Log-Softmax and Append Star Column
      final windowEmissions = Float32List(chunkFrames * 32);
      for (var t = 0; t < chunkFrames; t++) {
        final frameOffset31 = t * 31;
        final frameOffset32 = t * 32;

        // Find max for numerical stability
        var maxLogit = -double.infinity;
        for (var c = 0; c < 31; c++) {
          final val = chunkData[frameOffset31 + c];
          if (val > maxLogit) maxLogit = val;
        }

        var sumExp = 0.0;
        for (var c = 0; c < 31; c++) {
          sumExp += math.exp(chunkData[frameOffset31 + c] - maxLogit);
        }
        final logSumExp = maxLogit + math.log(sumExp);

        for (var c = 0; c < 31; c++) {
          windowEmissions[frameOffset32 + c] =
              chunkData[frameOffset31 + c] - logSumExp;
        }
        // Star wildcard column 31
        windowEmissions[frameOffset32 + 31] = starScore;
      }

      // 4. Stitching: Trim Context Frames
      final leftTrimSamples = winStart - ctxStart;
      final rightTrimSamples = ctxEnd - winEnd;

      final leftTrimFrames = (leftTrimSamples / convStride).round();
      final rightTrimFrames = (rightTrimSamples / convStride).round();

      final validStartFrame = leftTrimFrames.clamp(0, chunkFrames);
      final validEndFrame = (chunkFrames - rightTrimFrames).clamp(validStartFrame, chunkFrames);

      final validFramesCount = validEndFrame - validStartFrame;
      if (validFramesCount > 0) {
        final validSlice = Float32List(validFramesCount * 32);
        validSlice.setRange(
          0,
          validSlice.length,
          windowEmissions,
          validStartFrame * 32,
        );
        allFrames.add(validSlice);
      }

      onProgress?.call((w + 1) / totalWindows);
    }

    // Concatenate all valid frame slices
    var totalValidFrames = 0;
    for (final slice in allFrames) {
      totalValidFrames += slice.length ~/ 32;
    }

    final fullData = Float32List(totalValidFrames * 32);
    var destOffset = 0;
    for (final slice in allFrames) {
      fullData.setRange(destOffset, destOffset + slice.length, slice);
      destOffset += slice.length;
    }

    return EmissionsOutput(
      data: fullData,
      totalFrames: totalValidFrames,
    );
  }
}
