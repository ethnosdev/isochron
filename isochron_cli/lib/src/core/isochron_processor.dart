import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'package:isochron_cli/src/math/boundary_snapper.dart';
import 'package:path/path.dart' as p;
import '../core/fragment.dart';
import '../core/text_parser.dart';
import '../core/time_projector.dart';
import '../core/pin_boundary_enforcer.dart';
import '../core/drivers.dart';
import '../synthesis/anchor_generator.dart';
import '../math/mfcc_extractor.dart';
import '../math/dtw_aligner.dart';
import 'transliterator.dart';

class IsochronProcessor {
  static Future<List<Fragment>> process({
    required String text,
    required String audioPath,
    required Directory workDir,
    required AudioDriver audioDriver,
    required TtsDriver ttsDriver,
    Map<String, String>? transliterationRules,
    ProgressCallback? onProgress,
    Map<int, ({double start, double end})>? pinnedTimings,
  }) async {
    final stopwatch = Stopwatch()..start();

    void logStep(String step) {
      log('[Isochron] $step took ${stopwatch.elapsedMilliseconds}ms');
      stopwatch.reset();
    }

    // 1. Text Parsing (0.00 - 0.05)
    onProgress?.call("Parsing Text...", 0.0);
    final fragments = TextParser.parse(text);
    if (fragments.isEmpty) throw Exception("No text found in file.");

    if (transliterationRules != null && transliterationRules.isNotEmpty) {
      for (final frag in fragments) {
        frag.spokenText =
            Transliterator.convert(frag.text, transliterationRules);
      }
    }
    logStep("Text Parsing");

    // 2. Generate Anchor Audio (0.05 - 0.55)
    onProgress?.call("Generating Anchor Audio...", 0.05);
    final anchorGen =
        AnchorGenerator(audioDriver: audioDriver, ttsDriver: ttsDriver);
    final anchorFile =
        await anchorGen.generate(fragments, workDir, onProgress: (pct) {
      onProgress?.call("Generating Anchor Audio...", 0.05 + (pct * 0.50));
    });
    logStep("Anchor Generation");

    // 3. Normalize User Audio (0.55 - 0.60)
    onProgress?.call("Processing User Audio...", 0.55);
    final userAudioWav = File(p.join(workDir.path, 'user_mono_16k.wav'));
    await audioDriver.normalize(audioPath, userAudioWav.path);
    logStep("User Audio Normalization");

    // 4. Feature Extraction (0.60 - 0.70)
    onProgress?.call("Extracting Anchor Features...", 0.60);
    final anchorMfcc =
        MfccExtractor.extract(_readWavData(anchorFile), onProgress: (pct) {
      onProgress?.call("Extracting Anchor Features...", 0.60 + (pct * 0.05));
    });

    onProgress?.call("Extracting User Features...", 0.65);
    final userMfcc =
        MfccExtractor.extract(_readWavData(userAudioWav), onProgress: (pct) {
      onProgress?.call("Extracting User Features...", 0.65 + (pct * 0.05));
    });
    logStep("Feature Extraction");

    const double frameStride = 0.010;
    final audioBytes = _readWavData(userAudioWav);

    // 5. Dynamic Time Warping (DTW) Alignment (0.70 - 0.95)
    onProgress?.call("Aligning...", 0.70);
    if (pinnedTimings == null || pinnedTimings.isEmpty) {
      final path =
          DtwAligner.align(userMfcc, anchorMfcc, onProgress: (status, pct) {
        onProgress?.call(status, 0.70 + (pct * 0.25));
      });
      TimeProjector.project(fragments, path);
    } else {
      for (final entry in pinnedTimings.entries) {
        final idx = entry.key;
        if (idx >= 0 && idx < fragments.length) {
          fragments[idx]
              .setPinnedTiming(start: entry.value.start, end: entry.value.end);
        }
      }

      final sortedPins = (pinnedTimings.keys.toList()..sort());
      final boundaries = <int>[-1, ...sortedPins, fragments.length];

      for (int b = 0; b < boundaries.length - 1; b++) {
        final prevPin = boundaries[b];
        final nextPin = boundaries[b + 1];
        final segFragStart = prevPin + 1;
        final segFragEnd = nextPin - 1;
        if (segFragStart > segFragEnd) continue;

        final int realFrameStart = prevPin == -1
            ? 0
            : (fragments[prevPin].pinnedEnd! / frameStride).round();
        final int realFrameEnd = nextPin == fragments.length
            ? userMfcc.length
            : (fragments[nextPin].pinnedStart! / frameStride).round();
        final int anchorFrameStart = prevPin == -1
            ? 0
            : (fragments[prevPin].anchorEnd / frameStride).round();
        final int anchorFrameEnd = nextPin == fragments.length
            ? anchorMfcc.length
            : (fragments[nextPin].anchorStart / frameStride).round();

        if (realFrameStart >= realFrameEnd ||
            anchorFrameStart >= anchorFrameEnd) continue;

        final realSlice = userMfcc.sublist(
            realFrameStart, realFrameEnd.clamp(0, userMfcc.length));
        final anchorSlice = anchorMfcc.sublist(
            anchorFrameStart, anchorFrameEnd.clamp(0, anchorMfcc.length));

        final relativePath = DtwAligner.align(realSlice, anchorSlice);
        final offsetPath = relativePath
            .map((p) => AlignmentPoint(
                p.realIndex + realFrameStart, p.anchorIndex + anchorFrameStart))
            .toList();

        TimeProjector.project(
            fragments.sublist(segFragStart, segFragEnd + 1), offsetPath,
            frameStride: frameStride);
      }

      for (final frag in fragments) {
        if (frag.isPinned)
          frag.setRealTiming(start: frag.pinnedStart!, end: frag.pinnedEnd!);
      }
    }
    logStep("DTW Alignment");

    // 6. Post-Processing (0.95 - 1.0)
    onProgress?.call('Refining Timestamps...', 0.95);
    BoundarySnapper.snap(fragments, audioBytes, 16000);
    if (pinnedTimings != null && pinnedTimings.isNotEmpty) {
      PinBoundaryEnforcer.enforce(fragments);
    }

    onProgress?.call("Done", 1.0);
    logStep("Full Pipeline Cleanup");
    return fragments;
  }

  static Float64List _readWavData(File f) {
    final bytes = f.readAsBytesSync();
    if (bytes.length < 44) return Float64List(0);
    final int16Data = bytes.buffer.asInt16List(44);
    final floatData = Float64List(int16Data.length);
    for (int i = 0; i < int16Data.length; i++) {
      floatData[i] = int16Data[i] / 32768.0;
    }
    return floatData;
  }
}
