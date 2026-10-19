import 'dart:io';
import 'package:path/path.dart' as p;
import '../audio/audio_signal.dart';
import '../audio/pause_detector.dart';
import '../audio/wav_reader.dart';
import '../core/fragment.dart';
import '../core/text_parser.dart';
import '../platform/mac_drivers.dart';
import 'boundary_placer.dart';
import 'constrained_aligner.dart';
import 'ctc_aligner.dart';
import 'find_unread.dart';
import 'mms_tokenizer.dart';
import 'model_manager.dart';
import 'onnx_emissions_engine.dart';
import 'pause_snapper.dart';
import 'quality_analyzer.dart';
import '../ort/ort_session.dart';

class MmsPipelineOptions {
  final String? languageCode;
  final double leadInSeconds;
  final double starScore;
  final double leadStarScore;
  final StarPlacement starPlacement;
  final double windowSeconds;
  final double contextSeconds;
  final String? modelPath;
  final ModelVariant modelVariant;
  final int? intraOpThreads;
  final bool snapToPauses;
  final double pauseSearchWindowSeconds;
  final double minPauseDurationSeconds;
  final bool keepEdits;
  final bool detectOmissions;
  final bool computeQualityFlags;

  const MmsPipelineOptions({
    this.languageCode,
    this.leadInSeconds = 0.19,
    this.starScore = -2.0,
    this.leadStarScore = 0.0,
    this.starPlacement = StarPlacement.segment,
    this.windowSeconds = 30.0,
    this.contextSeconds = 2.0,
    this.modelPath,
    this.modelVariant = ModelVariant.int8,
    this.intraOpThreads,
    this.snapToPauses = true,
    this.pauseSearchWindowSeconds = 1.0,
    this.minPauseDurationSeconds = 0.100,
    this.keepEdits = false,
    this.detectOmissions = true,
    this.computeQualityFlags = true,
  });

  MmsPipelineOptions copyWith({
    String? languageCode,
    double? leadInSeconds,
    double? starScore,
    double? leadStarScore,
    StarPlacement? starPlacement,
    double? windowSeconds,
    double? contextSeconds,
    String? modelPath,
    ModelVariant? modelVariant,
    int? intraOpThreads,
    bool? snapToPauses,
    double? pauseSearchWindowSeconds,
    double? minPauseDurationSeconds,
    bool? keepEdits,
    bool? detectOmissions,
    bool? computeQualityFlags,
  }) {
    return MmsPipelineOptions(
      languageCode: languageCode ?? this.languageCode,
      leadInSeconds: leadInSeconds ?? this.leadInSeconds,
      starScore: starScore ?? this.starScore,
      leadStarScore: leadStarScore ?? this.leadStarScore,
      starPlacement: starPlacement ?? this.starPlacement,
      windowSeconds: windowSeconds ?? this.windowSeconds,
      contextSeconds: contextSeconds ?? this.contextSeconds,
      modelPath: modelPath ?? this.modelPath,
      modelVariant: modelVariant ?? this.modelVariant,
      intraOpThreads: intraOpThreads ?? this.intraOpThreads,
      snapToPauses: snapToPauses ?? this.snapToPauses,
      pauseSearchWindowSeconds:
          pauseSearchWindowSeconds ?? this.pauseSearchWindowSeconds,
      minPauseDurationSeconds:
          minPauseDurationSeconds ?? this.minPauseDurationSeconds,
      keepEdits: keepEdits ?? this.keepEdits,
      detectOmissions: detectOmissions ?? this.detectOmissions,
      computeQualityFlags: computeQualityFlags ?? this.computeQualityFlags,
    );
  }
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

      // Analyze audio signal and detect pauses once for snapping and quality analysis
      final signal = AudioSignal.analyze(audioData.samples, sampleRate: audioData.sampleRate);
      final detector = PauseDetector(minDurationSeconds: options.minPauseDurationSeconds);
      final pauses = detector.detectPauses(signal);

      List<PlacedVerseTiming> placedBoundaries;
      List<TokenTiming> tokenTimings;

      final hasLockedEdits = options.keepEdits &&
          fragments.any((f) =>
              f.status == FragmentStatus.edited ||
              f.status == FragmentStatus.reviewed);

      if (hasLockedEdits) {
        onProgress?.call('Aligning with locked edits...', 0.80);
        final constrainedAligner = ConstrainedAligner(tokenizer: _tokenizer);
        placedBoundaries = constrainedAligner.alignConstrained(
          fragments: fragments,
          emissions: emissions,
          pauses: pauses,
          trackDurationSeconds: audioData.durationSeconds,
          options: options,
          onProgress: onProgress,
        );
        tokenTimings = const [];
        stageTimes['ctc_viterbi'] = sw.elapsedMilliseconds;
        sw.reset();
      } else {
        // 5. CTC Viterbi Forced Alignment Trellis
        onProgress?.call('Solving CTC Viterbi trellis...', 0.80);
        final alignmentResult = CtcAligner.align(
          emissions: emissions,
          targetTokenIds: tokenOutput.tokenIds,
          targetTokenChars: tokenOutput.tokenChars,
          leadStarScore: options.leadStarScore,
        );
        tokenTimings = alignmentResult.tokenTimings;
        stageTimes['ctc_viterbi'] = sw.elapsedMilliseconds;
        sw.reset();

        // 6. Boundary Placement
        onProgress?.call('Placing boundaries...', 0.95);
        placedBoundaries = BoundaryPlacer.placeBoundaries(
          verseRanges: tokenOutput.verseRanges,
          tokenTimings: alignmentResult.tokenTimings,
          trackDurationSeconds: audioData.durationSeconds,
          leadInSeconds: options.leadInSeconds,
        );

        // Phase 2: Pause-aware boundary snapping
        if (options.snapToPauses) {
          onProgress?.call('Snapping to acoustic pauses...', 0.98);
          final snapper = PauseSnapper(
            searchWindowSeconds: options.pauseSearchWindowSeconds,
            leadInSeconds: options.leadInSeconds,
          );

          final rawStarts = placedBoundaries.map((b) => b.start).toList();
          final speechStarts =
              placedBoundaries.map((b) => b.speechStart).toList();
          final snappedStarts = snapper.snapBoundaries(
            rawStarts,
            pauses,
            speechStarts: speechStarts,
          );

          final snappedBoundaries = <PlacedVerseTiming>[];
          for (int i = 0; i < placedBoundaries.length; i++) {
            final curStart = snappedStarts[i];
            final curEnd = (i + 1 < placedBoundaries.length)
                ? snappedStarts[i + 1]
                : audioData.durationSeconds;
            final orig = placedBoundaries[i];
            snappedBoundaries.add(PlacedVerseTiming(
              index: orig.index,
              start: curStart,
              end: curEnd,
              speechStart: orig.speechStart,
              speechEnd: orig.speechEnd,
              meanLogProb: orig.meanLogProb,
              warnings: orig.warnings,
              flags: orig.flags,
              confidence: orig.confidence,
            ));
          }
          placedBoundaries = snappedBoundaries;
        }
      }

      // Phase 2 Candidate 4: Unread omission detection
      if (options.detectOmissions) {
        final unreadDetector = const UnreadDetector();
        placedBoundaries = unreadDetector.detectOmissions(
          timings: placedBoundaries,
          fragments: fragments,
          trackDurationSeconds: audioData.durationSeconds,
          pauses: pauses,
          leadInSeconds: options.leadInSeconds,
        );
      }

      // Phase 3: Diagnostic anomaly flags & confidence scoring
      if (options.computeQualityFlags) {
        placedBoundaries = QualityAnalyzer.analyze(
          timings: placedBoundaries,
          fragments: fragments,
          pauses: pauses,
        );
      }

      stageTimes['boundary_placement'] = sw.elapsedMilliseconds;
      sw.reset();

      // 7. Update Fragments
      final updatedFragments = <Fragment>[];
      for (var i = 0; i < fragments.length; i++) {
        final orig = fragments[i];
        final placed = placedBoundaries[i];

        final bool isUserLocked = options.keepEdits &&
            (orig.status == FragmentStatus.edited ||
                orig.status == FragmentStatus.reviewed);

        final f = orig.copyWith(
          realStart: placed.start,
          realEnd: placed.end,
          autoStart: isUserLocked ? orig.autoStart : placed.start,
          status: isUserLocked ? orig.status : FragmentStatus.auto,
          confidence: placed.confidence,
          flags: placed.flags,
          warnings: placed.warnings,
        );
        updatedFragments.add(f);
      }

      onProgress?.call('Done', 1.0);
      return MmsPipelineResult(
        fragments: updatedFragments,
        tokenTimings: tokenTimings,
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
