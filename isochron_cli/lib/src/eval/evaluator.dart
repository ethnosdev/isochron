import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:path/path.dart' as p;
import '../core/text_parser.dart';
import '../mms/mms_pipeline.dart';

class VerseErrorDetail {
  final int verseIndex;
  final String text;
  final double predStart;
  final double truthStart;
  final double errorSeconds;

  double get absErrorSeconds => errorSeconds.abs();

  const VerseErrorDetail({
    required this.verseIndex,
    required this.text,
    required this.predStart,
    required this.truthStart,
    required this.errorSeconds,
  });
}

class FixtureMetrics {
  final String fixtureName;
  final String languageCode;
  final int totalVerses;
  final int evaluatedVerses;
  final double meanAbsError;
  final double medianAbsError;
  final double p90AbsError;
  final double p95AbsError;
  final double signedMeanError;
  final double pctWithin100ms;
  final double pctWithin200ms;
  final double pctWithin500ms;
  final int elapsedMs;
  final List<VerseErrorDetail> verseErrors;
  final List<VerseErrorDetail> worstErrors;

  const FixtureMetrics({
    required this.fixtureName,
    required this.languageCode,
    required this.totalVerses,
    required this.evaluatedVerses,
    required this.meanAbsError,
    required this.medianAbsError,
    required this.p90AbsError,
    required this.p95AbsError,
    required this.signedMeanError,
    required this.pctWithin100ms,
    required this.pctWithin200ms,
    required this.pctWithin500ms,
    required this.elapsedMs,
    required this.verseErrors,
    required this.worstErrors,
  });
}

class AggregateMetrics {
  final int fixtureCount;
  final int totalVerses;
  final double meanAbsError;
  final double medianAbsError;
  final double p90AbsError;
  final double p95AbsError;
  final double signedMeanError;
  final double pctWithin100ms;
  final double pctWithin200ms;
  final double pctWithin500ms;
  final int totalElapsedMs;
  final List<FixtureMetrics> fixtureResults;

  const AggregateMetrics({
    required this.fixtureCount,
    required this.totalVerses,
    required this.meanAbsError,
    required this.medianAbsError,
    required this.p90AbsError,
    required this.p95AbsError,
    required this.signedMeanError,
    required this.pctWithin100ms,
    required this.pctWithin200ms,
    required this.pctWithin500ms,
    required this.totalElapsedMs,
    required this.fixtureResults,
  });
}

class Evaluator {
  final MmsPipeline _mmsPipeline;

  Evaluator({MmsPipeline? mmsPipeline})
      : _mmsPipeline = mmsPipeline ?? MmsPipeline();

  /// Evaluates all fixtures in [fixturesDir].
  Future<AggregateMetrics> evaluateDirectory(
    Directory fixturesDir, {
    MmsPipelineOptions mmsOptions = const MmsPipelineOptions(),
    void Function(String fixtureName, double progress)? onProgress,
  }) async {
    final subdirs = fixturesDir
        .listSync()
        .whereType<Directory>()
        .where((d) => !p.basename(d.path).startsWith('.'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    final results = <FixtureMetrics>[];
    for (var i = 0; i < subdirs.length; i++) {
      final dir = subdirs[i];
      final fixtureName = p.basename(dir.path);
      onProgress?.call(fixtureName, i / subdirs.length);

      final metrics = await evaluateFixture(
        dir,
        mmsOptions: mmsOptions,
      );
      results.add(metrics);
    }
    onProgress?.call('Completed', 1.0);

    return _computeAggregate(results);
  }

  /// Evaluates a single fixture folder.
  Future<FixtureMetrics> evaluateFixture(
    Directory fixtureDir, {
    MmsPipelineOptions mmsOptions = const MmsPipelineOptions(),
  }) async {
    final fixtureName = p.basename(fixtureDir.path);

    // Locate files
    final audioFiles = fixtureDir
        .listSync()
        .whereType<File>()
        .where((f) => RegExp(r'\.(mp3|wav|m4a|aac|flac)$', caseSensitive: false).hasMatch(f.path))
        .toList();
    if (audioFiles.isEmpty) {
      throw FileSystemException('No audio file found in ${fixtureDir.path}');
    }
    final audioFile = audioFiles.first;

    final textFile = File(p.join(fixtureDir.path, 'text.txt'));
    final truthFile = File(p.join(fixtureDir.path, 'truth.json'));
    final manifestFile = File(p.join(fixtureDir.path, 'manifest.json'));

    if (!await textFile.exists()) {
      throw FileSystemException('text.txt not found in ${fixtureDir.path}');
    }
    if (!await truthFile.exists()) {
      throw FileSystemException('truth.json not found in ${fixtureDir.path}');
    }

    String? lang = mmsOptions.languageCode;
    bool hasIds = false;
    if (await manifestFile.exists()) {
      final manifestJson =
          jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      lang ??= manifestJson['languageCode'] as String?;
      hasIds = manifestJson['hasIds'] as bool? ?? false;
    }

    final rawText = await textFile.readAsString();
    final fragments = TextParser.parse(rawText, hasIds: hasIds);
    final truthList =
        (jsonDecode(await truthFile.readAsString()) as List)
            .cast<Map<String, dynamic>>();

    final sw = Stopwatch()..start();
    final pipelineResult = await _mmsPipeline.process(
      fragments: fragments,
      audioPath: audioFile.path,
      options: mmsOptions.copyWith(languageCode: lang),
    );
    sw.stop();

    final predictions = pipelineResult.fragments;
    final verseErrors = <VerseErrorDetail>[];

    final minCount = math.min(predictions.length, truthList.length);
    for (var i = 0; i < minCount; i++) {
      final truth = truthList[i];
      final truthStart = (truth['start'] as num).toDouble();
      // Skip verses unread/omitted in ground truth (-1)
      if (truthStart < 0) continue;

      final predStart = predictions[i].realStart;
      final error = predStart - truthStart;

      verseErrors.add(
        VerseErrorDetail(
          verseIndex: i,
          text: predictions[i].text,
          predStart: predStart,
          truthStart: truthStart,
          errorSeconds: error,
        ),
      );
    }

    final sortedAbs = verseErrors.map((e) => e.absErrorSeconds).toList()..sort();
    final sortedByAbsError = List<VerseErrorDetail>.from(verseErrors)
      ..sort((a, b) => b.absErrorSeconds.compareTo(a.absErrorSeconds));

    final count = verseErrors.length;
    double meanAbs = 0.0;
    double signedMean = 0.0;
    int within100 = 0;
    int within200 = 0;
    int within500 = 0;

    for (final err in verseErrors) {
      meanAbs += err.absErrorSeconds;
      signedMean += err.errorSeconds;
      if (err.absErrorSeconds <= 0.10) within100++;
      if (err.absErrorSeconds <= 0.20) within200++;
      if (err.absErrorSeconds <= 0.50) within500++;
    }

    if (count > 0) {
      meanAbs /= count;
      signedMean /= count;
    }

    final medianAbs = count > 0 ? _percentile(sortedAbs, 0.50) : 0.0;
    final p90Abs = count > 0 ? _percentile(sortedAbs, 0.90) : 0.0;
    final p95Abs = count > 0 ? _percentile(sortedAbs, 0.95) : 0.0;

    return FixtureMetrics(
      fixtureName: fixtureName,
      languageCode: lang ?? 'unknown',
      totalVerses: fragments.length,
      evaluatedVerses: count,
      meanAbsError: meanAbs,
      medianAbsError: medianAbs,
      p90AbsError: p90Abs,
      p95AbsError: p95Abs,
      signedMeanError: signedMean,
      pctWithin100ms: count > 0 ? (within100 / count * 100) : 0.0,
      pctWithin200ms: count > 0 ? (within200 / count * 100) : 0.0,
      pctWithin500ms: count > 0 ? (within500 / count * 100) : 0.0,
      elapsedMs: sw.elapsedMilliseconds,
      verseErrors: verseErrors,
      worstErrors: sortedByAbsError.take(5).toList(),
    );
  }

  static double _percentile(List<double> sorted, double p) {
    if (sorted.isEmpty) return 0.0;
    final idx = ((sorted.length - 1) * p).round();
    return sorted[idx.clamp(0, sorted.length - 1)];
  }

  static AggregateMetrics _computeAggregate(List<FixtureMetrics> fixtures) {
    var totalVerses = 0;
    var totalElapsed = 0;
    final allAbsErrors = <double>[];
    var totalSigned = 0.0;
    var within100 = 0;
    var within200 = 0;
    var within500 = 0;

    for (final f in fixtures) {
      totalElapsed += f.elapsedMs;
      for (final e in f.verseErrors) {
        totalVerses++;
        allAbsErrors.add(e.absErrorSeconds);
        totalSigned += e.errorSeconds;
        if (e.absErrorSeconds <= 0.10) within100++;
        if (e.absErrorSeconds <= 0.20) within200++;
        if (e.absErrorSeconds <= 0.50) within500++;
      }
    }

    allAbsErrors.sort();
    final meanAbs = totalVerses > 0
        ? allAbsErrors.reduce((a, b) => a + b) / totalVerses
        : 0.0;
    final signedMean = totalVerses > 0 ? totalSigned / totalVerses : 0.0;

    return AggregateMetrics(
      fixtureCount: fixtures.length,
      totalVerses: totalVerses,
      meanAbsError: meanAbs,
      medianAbsError: _percentile(allAbsErrors, 0.50),
      p90AbsError: _percentile(allAbsErrors, 0.90),
      p95AbsError: _percentile(allAbsErrors, 0.95),
      signedMeanError: signedMean,
      pctWithin100ms: totalVerses > 0 ? (within100 / totalVerses * 100) : 0.0,
      pctWithin200ms: totalVerses > 0 ? (within200 / totalVerses * 100) : 0.0,
      pctWithin500ms: totalVerses > 0 ? (within500 / totalVerses * 100) : 0.0,
      totalElapsedMs: totalElapsed,
      fixtureResults: fixtures,
    );
  }

  /// Formats the evaluation results as a clean ASCII report table.
  static String formatReport(AggregateMetrics agg) {
    final buf = StringBuffer();
    buf.writeln('========================================================================================');
    buf.writeln('                                  EVALUATION REPORT                                     ');
    buf.writeln('========================================================================================');
    buf.writeln(
      'Fixture'.padRight(22) +
      'Verses'.padLeft(8) +
      'Median(s)'.padLeft(12) +
      'Mean(s)'.padLeft(10) +
      'p95(s)'.padLeft(10) +
      '<=0.2s %'.padLeft(11) +
      'Bias(s)'.padLeft(10) +
      'Time'.padLeft(9),
    );
    buf.writeln('----------------------------------------------------------------------------------------');

    for (final f in agg.fixtureResults) {
      buf.writeln(
        f.fixtureName.padRight(22) +
        f.evaluatedVerses.toString().padLeft(8) +
        f.medianAbsError.toStringAsFixed(3).padLeft(12) +
        f.meanAbsError.toStringAsFixed(3).padLeft(10) +
        f.p95AbsError.toStringAsFixed(3).padLeft(10) +
        '${f.pctWithin200ms.toStringAsFixed(1)}%'.padLeft(11) +
        (f.signedMeanError >= 0 ? '+${f.signedMeanError.toStringAsFixed(3)}' : f.signedMeanError.toStringAsFixed(3)).padLeft(10) +
        '${(f.elapsedMs / 1000).toStringAsFixed(1)}s'.padLeft(9),
      );
    }

    buf.writeln('========================================================================================');
    buf.writeln(
      'AGGREGATE (${agg.fixtureCount} fix)'.padRight(22) +
      agg.totalVerses.toString().padLeft(8) +
      agg.medianAbsError.toStringAsFixed(3).padLeft(12) +
      agg.meanAbsError.toStringAsFixed(3).padLeft(10) +
      agg.p95AbsError.toStringAsFixed(3).padLeft(10) +
      '${agg.pctWithin200ms.toStringAsFixed(1)}%'.padLeft(11) +
      (agg.signedMeanError >= 0 ? '+${agg.signedMeanError.toStringAsFixed(3)}' : agg.signedMeanError.toStringAsFixed(3)).padLeft(10) +
      '${(agg.totalElapsedMs / 1000).toStringAsFixed(1)}s'.padLeft(9),
    );
    buf.writeln('========================================================================================\n');

    return buf.toString();
  }

  /// Exports verse-level details to a CSV file.
  static Future<void> exportCsv(AggregateMetrics agg, File csvFile) async {
    final sink = csvFile.openWrite();
    sink.writeln('fixture,verse_index,text,pred_start,truth_start,error_seconds,abs_error_seconds');
    for (final f in agg.fixtureResults) {
      for (final e in f.verseErrors) {
        final escapedText = '"${e.text.replaceAll('"', '""')}"';
        sink.writeln(
          '${f.fixtureName},${e.verseIndex},$escapedText,${e.predStart.toStringAsFixed(3)},'
          '${e.truthStart.toStringAsFixed(3)},${e.errorSeconds.toStringAsFixed(3)},${e.absErrorSeconds.toStringAsFixed(3)}',
        );
      }
    }
    await sink.flush();
    await sink.close();
  }
}

extension on MmsPipelineOptions {
  MmsPipelineOptions copyWith({String? languageCode}) {
    return MmsPipelineOptions(
      languageCode: languageCode ?? this.languageCode,
      leadInSeconds: leadInSeconds,
      starScore: starScore,
      starPlacement: starPlacement,
      windowSeconds: windowSeconds,
      contextSeconds: contextSeconds,
      modelPath: modelPath,
      modelVariant: modelVariant,
      intraOpThreads: intraOpThreads,
    );
  }
}
