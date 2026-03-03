import 'dart:io';
import 'dart:typed_data';
import 'package:isochron_cli/src/math/boundary_snapper.dart';
import 'package:path/path.dart' as p;
import '../core/fragment.dart';
import '../core/text_parser.dart';
import '../core/time_projector.dart';
import '../synthesis/anchor_generator.dart';
import '../math/mfcc_extractor.dart';
import '../math/dtw_aligner.dart';
import 'transliterator.dart';

class IsochronProcessor {
  /// Runs the full alignment pipeline.
  ///
  /// [workDir]: Temporary directory for intermediate files.
  /// [ffmpegPath]: Path or command for FFmpeg (default 'ffmpeg').
  /// [espeakPath]: Path or command for eSpeak (default 'espeak-ng').
  static Future<List<Fragment>> process({
    required String text,
    required String audioPath,
    required Directory workDir,
    String ffmpegPath = 'ffmpeg',
    String espeakPath = 'espeak-ng',
    Map<String, String>? transliterationRules,
    ProgressCallback? onProgress,

    /// Optional map of fragment index → known-correct {start, end} in seconds.
    /// Pinned fragments are used as hard boundaries; all other fragments are
    /// aligned via DTW within the windows that pins define.
    Map<int, ({double start, double end})>? pinnedTimings,
  }) async {
    onProgress?.call("Parsing Text...", 0.05);
    final fragments = TextParser.parse(text);
    if (fragments.isEmpty) throw Exception("No text found in file.");

    // Apply rules if they exist
    if (transliterationRules != null && transliterationRules.isNotEmpty) {
      for (final frag in fragments) {
        frag.spokenText =
            Transliterator.convert(frag.text, transliterationRules);
      }
    }

    // Generate Anchor (Pass custom binary path)
    onProgress?.call("Generating Anchor Audio...", 0.1);
    final anchorGen = AnchorGenerator(binaryPath: espeakPath);
    final anchorFile = await anchorGen.generate(fragments, workDir);

    // Normalize User Audio (Pass custom binary path)
    onProgress?.call("Processing User Audio...", 0.2);
    final userAudioWav = File(p.join(workDir.path, 'user_mono_16k.wav'));

    // We execute FFmpeg manually here to ensure we use the dynamic path
    final result = await Process.run(ffmpegPath, [
      '-y',
      '-i',
      audioPath,
      '-ac',
      '1',
      '-ar',
      '16000',
      '-f',
      'wav',
      '-acodec',
      'pcm_s16le',
      userAudioWav.path
    ]);

    if (result.exitCode != 0) {
      throw Exception('FFmpeg failed: ${result.stderr}');
    }

    // Feature Extraction
    onProgress?.call("Extracting Anchor Features...", 0.25);
    final anchorMfcc = MfccExtractor.extract(
      _readWavData(anchorFile),
      onProgress: (pct) {
        // Map 0.0-1.0 to 0.25-0.35
        onProgress?.call("Extracting Anchor Features...", 0.25 + (pct * 0.10));
      },
    );

    onProgress?.call("Extracting User Features...", 0.35);
    final userMfcc = MfccExtractor.extract(
      _readWavData(userAudioWav),
      onProgress: (pct) {
        // Map 0.0-1.0 to 0.35-0.45
        onProgress?.call("Extracting User Features...", 0.35 + (pct * 0.10));
      },
    );

    const double frameStride = 0.010;
    final audioBytes = _readWavData(userAudioWav);

    if (pinnedTimings == null || pinnedTimings.isEmpty) {
      // ── Original single-pass path ──────────────────────────────────────────
      final path =
          DtwAligner.align(userMfcc, anchorMfcc, onProgress: (status, pct) {
        final overall = 0.45 + (pct * 0.50);
        onProgress?.call(status, overall);
      });
      onProgress?.call('Finalizing...', 0.95);
      TimeProjector.project(fragments, path);
    } else {
      // ── Segmented DTW: one DTW pass per gap between pinned fragments ────────
      //
      // 1. Stamp each pinned fragment with its user-provided times.
      for (final entry in pinnedTimings.entries) {
        final idx = entry.key;
        if (idx >= 0 && idx < fragments.length) {
          fragments[idx]
              .setPinnedTiming(start: entry.value.start, end: entry.value.end);
        }
      }

      // 2. Build the ordered list of boundary indices.
      //    Sentinel -1 represents "before the first fragment" and
      //    fragments.length represents "after the last fragment".
      final sortedPins = (pinnedTimings.keys.toList()..sort());
      final boundaries = <int>[-1, ...sortedPins, fragments.length];

      onProgress?.call('Aligning segments...', 0.45);

      // 3. For each gap between consecutive boundaries, run a scoped DTW.
      for (int b = 0; b < boundaries.length - 1; b++) {
        final prevPin = boundaries[b]; // -1 or a pinned fragment index
        final nextPin = boundaries[b + 1]; // pinned fragment index or length

        // The unaligned fragments live strictly between the two pins.
        final segFragStart = prevPin + 1;
        final segFragEnd = nextPin - 1; // inclusive
        if (segFragStart > segFragEnd) continue; // nothing between these pins

        // Real-audio frame window.
        final int realFrameStart = prevPin == -1
            ? 0
            : (fragments[prevPin].pinnedEnd! / frameStride).round();
        final int realFrameEnd = nextPin == fragments.length
            ? userMfcc.length
            : (fragments[nextPin].pinnedStart! / frameStride).round();

        // Anchor frame window.
        final int anchorFrameStart = prevPin == -1
            ? 0
            : (fragments[prevPin].anchorEnd / frameStride).round();
        final int anchorFrameEnd = nextPin == fragments.length
            ? anchorMfcc.length
            : (fragments[nextPin].anchorStart / frameStride).round();

        // Guard against degenerate slices.
        if (realFrameStart >= realFrameEnd ||
            anchorFrameStart >= anchorFrameEnd) {
          continue;
        }

        final realSlice = userMfcc.sublist(
            realFrameStart, realFrameEnd.clamp(0, userMfcc.length));
        final anchorSlice = anchorMfcc.sublist(
            anchorFrameStart, anchorFrameEnd.clamp(0, anchorMfcc.length));
        if (realSlice.isEmpty || anchorSlice.isEmpty) {
          continue;
        }

        // Run DTW on the slice; indices are relative to slice start (0-based).
        final relativePath = DtwAligner.align(realSlice, anchorSlice);

        // Offset path back to absolute frame indices before projecting.
        final offsetPath = relativePath
            .map((p) => AlignmentPoint(
                  p.realIndex + realFrameStart,
                  p.anchorIndex + anchorFrameStart,
                ))
            .toList();

        final segFragments = fragments.sublist(segFragStart, segFragEnd + 1);
        TimeProjector.project(segFragments, offsetPath,
            frameStride: frameStride);
      }

      // 4. Apply pinned timings directly — these override anything DTW set.
      for (final frag in fragments) {
        if (frag.isPinned) {
          frag.setRealTiming(start: frag.pinnedStart!, end: frag.pinnedEnd!);
        }
      }

      onProgress?.call('Finalizing...', 0.95);
    }

    onProgress?.call('Refining Timestamps...', 0.98);
    BoundarySnapper.snap(fragments, audioBytes, 16000);

    onProgress?.call("Done", 1.0);
    return fragments;
  }

  // Helper to read WAV bytes safely
  static Float64List _readWavData(File f) {
    final bytes = f.readAsBytesSync();
    // Skip 44 byte header, view as Int16, convert to double
    if (bytes.length < 44) return Float64List(0);
    final int16Data = bytes.buffer.asInt16List(44);
    final floatData = Float64List(int16Data.length);
    for (int i = 0; i < int16Data.length; i++) {
      floatData[i] = int16Data[i] / 32768.0;
    }
    return floatData;
  }
}
