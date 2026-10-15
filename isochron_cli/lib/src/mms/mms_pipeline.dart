import 'dart:io';
import 'package:path/path.dart' as p;
import '../audio/wav_reader.dart';
import '../core/fragment.dart';
import '../core/text_parser.dart';
import '../platform/mac_drivers.dart';
import 'boundary_placer.dart';
import 'ctc_aligner.dart';
import 'mms_tokenizer.dart';
import 'model_manager.dart';
import 'onnx_emissions_engine.dart';
import '../ort/ort_session.dart';

class MmsPipelineOptions {
  final String? languageCode;
  final double leadInSeconds;
  final double starScore;
  final StarPlacement starPlacement;
  final double windowSeconds;
  final double contextSeconds;
  final String? modelPath;
  final ModelVariant modelVariant;
  final int? intraOpThreads;

  const MmsPipelineOptions({
    this.languageCode,
    this.leadInSeconds = 0.17,
    this.starScore = 0.0,
    this.starPlacement = StarPlacement.segment,
    this.windowSeconds = 30.0,
    this.contextSeconds = 2.0,
    this.modelPath,
    this.modelVariant = ModelVariant.int8,
    this.intraOpThreads,
  });
}

class MmsPipelineResult {
  final List<Fragment> fragments;
  final List<TokenTiming> tokenTimings;
  final double audioDurationSeconds;
  final Map<String, int> stageDurationsMs;

  const MmsPipelineResult({
    required this.fragments,
    required this.tokenTimings,
    required this.audioDurationSeconds,
    required this.stageDurationsMs,
  });
}

class MmsPipeline {
  final OrtSession? sharedSession;
  final MmsTokenizer _tokenizer;

  MmsPipeline({
    this.sharedSession,
    MmsTokenizer? tokenizer,
  })  : _tokenizer = tokenizer ?? MmsTokenizer();

  /// Aligns a list of input fragments against the provided audio file.
  Future<MmsPipelineResult> process({
    required List<Fragment> fragments,
    required String audioPath,
    MmsPipelineOptions options = const MmsPipelineOptions(),
    void Function(String stage, double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final stageTimes = <String, int>{};
    final sw = Stopwatch()..start();

    // 1. Audio Ingestion & Normalization
    onProgress?.call('Preparing audio...', 0.05);
    final isWav = audioPath.toLowerCase().endsWith('.wav');
    File? tempNormalizedWav;
    AudioData audioData;

    try {
      if (isWav) {
        try {
          audioData = await WavReader.read(File(audioPath), enforceMono16k: true);
        } catch (_) {
          // If WAV is not 16k mono (e.g. 44.1k stereo), re-encode with afconvert
          tempNormalizedWav = File(p.join(
            Directory.systemTemp.path,
            'mms_norm_${DateTime.now().millisecondsSinceEpoch}.wav',
          ));
          await MacAudioDriver().normalize(audioPath, tempNormalizedWav.path);
          audioData = await WavReader.read(tempNormalizedWav, enforceMono16k: true);
        }
      } else {
        // MP3, M4A, etc.
        tempNormalizedWav = File(p.join(
          Directory.systemTemp.path,
          'mms_norm_${DateTime.now().millisecondsSinceEpoch}.wav',
        ));
        await MacAudioDriver().normalize(audioPath, tempNormalizedWav.path);
        audioData = await WavReader.read(tempNormalizedWav, enforceMono16k: true);
      }
      stageTimes['audio_decode'] = sw.elapsedMilliseconds;
      sw.reset();

      if (isCancelled?.call() == true) throw Exception('Alignment cancelled');

      // 2. Tokenization with uroman
      onProgress?.call('Tokenizing text...', 0.15);
      final verseTexts = fragments.map((f) => f.text).toList();
      final tokenOutput = _tokenizer.tokenizeVerses(
        verseTexts,
        languageCode: options.languageCode,
        starPlacement: options.starPlacement,
      );
      stageTimes['tokenization'] = sw.elapsedMilliseconds;
      sw.reset();

      if (isCancelled?.call() == true) throw Exception('Alignment cancelled');

      // 3. Resolve Model & Session
      OrtSession activeSession;
      bool ownsSession = false;

      if (sharedSession != null) {
        activeSession = sharedSession!;
      } else {
        String effectiveModelPath;
        if (options.modelPath != null && File(options.modelPath!).existsSync()) {
          effectiveModelPath = options.modelPath!;
        } else {
          final manager = ModelManager();
          final file = manager.getFile(options.modelVariant);
          if (!await file.exists()) {
            throw StateError(
              'Model ${options.modelVariant.filename} not found at ${file.path}.\n'
              'Download it first via `isochron model download` or `ModelManager.download`.',
            );
          }
          effectiveModelPath = file.path;
        }

        activeSession = OrtSession.fromFile(
          effectiveModelPath,
          intraOpThreads: options.intraOpThreads,
        );
        ownsSession = true;
      }

      // 4. Acoustic Emissions Inference
      onProgress?.call('Running acoustic neural model...', 0.25);
      final emissionsEngine = OnnxEmissionsEngine(session: activeSession);
      EmissionsOutput emissions;
      try {
        emissions = emissionsEngine.computeEmissions(
          audioData.samples,
          windowSeconds: options.windowSeconds,
          contextSeconds: options.contextSeconds,
          starScore: options.starScore,
          onProgress: (pct) => onProgress?.call(
            'Running acoustic model (${(pct * 100).toStringAsFixed(0)}%)...',
            0.25 + pct * 0.50,
          ),
          isCancelled: isCancelled,
        );
      } finally {
        if (ownsSession) {
          activeSession.release();
        }
      }
      stageTimes['emissions_inference'] = sw.elapsedMilliseconds;
      sw.reset();

      if (isCancelled?.call() == true) throw Exception('Alignment cancelled');

      // 5. CTC Viterbi Forced Alignment Trellis
      onProgress?.call('Solving CTC Viterbi trellis...', 0.80);
      final alignmentResult = CtcAligner.align(
        emissions: emissions,
        targetTokenIds: tokenOutput.tokenIds,
        targetTokenChars: tokenOutput.tokenChars,
      );
      stageTimes['ctc_viterbi'] = sw.elapsedMilliseconds;
      sw.reset();

      // 6. Boundary Placement
      onProgress?.call('Placing boundaries...', 0.95);
      final placedBoundaries = BoundaryPlacer.placeBoundaries(
        verseRanges: tokenOutput.verseRanges,
        tokenTimings: alignmentResult.tokenTimings,
        trackDurationSeconds: audioData.durationSeconds,
        leadInSeconds: options.leadInSeconds,
      );
      stageTimes['boundary_placement'] = sw.elapsedMilliseconds;
      sw.reset();

      // 7. Update Fragments
      final updatedFragments = <Fragment>[];
      for (var i = 0; i < fragments.length; i++) {
        final orig = fragments[i];
        final placed = placedBoundaries[i];

        final f = orig.copyWith(
          realStart: placed.start,
          realEnd: placed.end,
          autoStart: placed.start,
          status: FragmentStatus.auto,
          warnings: placed.warnings,
        );
        updatedFragments.add(f);
      }

      onProgress?.call('Done', 1.0);
      return MmsPipelineResult(
        fragments: updatedFragments,
        tokenTimings: alignmentResult.tokenTimings,
        audioDurationSeconds: audioData.durationSeconds,
        stageDurationsMs: stageTimes,
      );
    } finally {
      if (tempNormalizedWav != null && await tempNormalizedWav.exists()) {
        try {
          await tempNormalizedWav.delete();
        } catch (_) {}
      }
    }
  }

  /// Convenience method to parse text from a string and align directly.
  Future<MmsPipelineResult> processText({
    required String rawText,
    required String audioPath,
    bool hasIds = false,
    MmsPipelineOptions options = const MmsPipelineOptions(),
    void Function(String stage, double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final fragments = TextParser.parse(rawText, hasIds: hasIds);
    return process(
      fragments: fragments,
      audioPath: audioPath,
      options: options,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
  }
}
