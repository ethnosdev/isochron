import 'dart:io';
import 'package:args/args.dart';
import 'package:isochron_cli/src/core/isochron_processor.dart';
import 'package:isochron_cli/src/platform/mac_drivers.dart';
import 'package:isochron_cli/src/core/text_parser.dart';
import 'package:isochron_cli/src/core/timing_export.dart';
import 'package:isochron_cli/src/eval/evaluator.dart';
import 'package:isochron_cli/src/mms/mms_pipeline.dart';
import 'package:isochron_cli/src/mms/mms_tokenizer.dart';
import 'package:isochron_cli/src/mms/model_manager.dart';

void main(List<String> arguments) async {
  if (arguments.isNotEmpty && arguments.first == 'eval') {
    await _handleEval(arguments.sublist(1));
    return;
  }

  if (arguments.isNotEmpty && arguments.first == 'model') {
    await _handleModel(arguments.sublist(1));
    return;
  }

  final parser = ArgParser()
    ..addOption('text', abbr: 't', help: 'Path to the input text file')
    ..addOption('audio', abbr: 'a', help: 'Path to the input audio file')
    ..addOption('output',
        abbr: 'o',
        help: 'Path to save output (JSON or timing text). '
            'If omitted, derived from --text filename and resolved format.')
    ..addOption('format',
        allowed: ['json', 'timing'],
        help: 'Output format. If omitted, inferred from --output extension.')
    ..addOption('lang', help: 'ISO 639-3 language code for uroman (e.g. ell, eng, heb)')
    ..addOption('lead-in',
        defaultsTo: '0.19',
        help: 'Seconds subtracted from speech onset for verse start (default 0.19)')
    ..addOption('star-score',
        defaultsTo: '-2.0',
        help: 'Wildcard star token log-probability (default -2.0)')
    ..addOption('star-placement',
        allowed: ['segment', 'edges'],
        defaultsTo: 'segment',
        help: 'Where to place wildcard tokens: "segment" (between all verses) or "edges" (start and end only)')
    ..addOption('model-path', help: 'Path to custom ONNX model file override')
    ..addOption('model-variant',
        allowed: ['int8', 'fp16', 'fp32'],
        defaultsTo: 'int8',
        help: 'Model variant to load from local cache: int8, fp16, fp32')
    ..addFlag('snap-pauses',
        help: 'Snap boundaries to qualifying acoustic pauses',
        defaultsTo: true)
    ..addFlag('has-ids',
        help:
            'Extract leading phrase ID from each line (tab or space separated). '
            'Auto-detected if source text contains tabs.',
        defaultsTo: false)
    ..addFlag('require-ids',
        help:
            'Abort export if any phrase ID is missing. '
            'Defaults to true when --has-ids is enabled or tab IDs are detected.',
        defaultsTo: false)
    ..addFlag('verbose',
        abbr: 'v', help: 'Show detailed logs', defaultsTo: false)
    ..addFlag('help',
        abbr: 'h', help: 'Show usage information', negatable: false);

  try {
    final results = parser.parse(arguments);

    if (results['help'] as bool) {
      print('Isochron Forced Aligner CLI');
      print('Commands:');
      print('  eval              Score aligners against ground-truth fixtures');
      print('  model             Manage MMS ONNX models (download, status, delete)');
      print('\nOptions for alignment:');
      print(parser.usage);
      exit(0);
    }

    final textPath = results['text'];
    final audioPath = results['audio'];
    final languageCode = results['lang'] as String?;
    final leadInSeconds = double.tryParse(results['lead-in'] ?? '0.19') ?? 0.19;
    final starScore = double.tryParse(results['star-score'] ?? '-2.0') ?? -2.0;
    final starPlacement = results['star-placement'] == 'edges'
        ? StarPlacement.edges
        : StarPlacement.segment;
    final modelPath = results['model-path'] as String?;
    final variantStr = results['model-variant'] as String? ?? 'int8';
    final modelVariant = ModelVariant.values.firstWhere(
      (v) => v.name == variantStr,
      orElse: () => ModelVariant.int8,
    );
    final snapPauses = results['snap-pauses'] as bool;

    final outputPath = results['output'] as String?;
    final requestedFormat = results['format'] as String?;
    final verbose = results['verbose'] as bool;

    if (textPath == null || audioPath == null) {
      stderr.writeln('Error: Both --text and --audio are required.');
      print(parser.usage);
      exit(1);
    }

    final effectiveOutput = TimingExport.resolveEffectiveOutput(
      explicitOutputPath: outputPath,
      requestedFormat: requestedFormat,
      sourceTextPath: textPath,
    );
    final effectiveFormat = effectiveOutput.format;
    final effectiveOutputPath = effectiveOutput.outputPath;

    final text = await File(textPath).readAsString();
    final hasTabs = detectTabDelimitedIds(text);
    final hasIdsFlag = results['has-ids'] as bool;
    final effectiveHasIds = hasIdsFlag || hasTabs;

    final requireIds = results.wasParsed('require-ids')
        ? (results['require-ids'] as bool)
        : effectiveHasIds;

    final workDir = await Directory.systemTemp.createTemp('isochron_cli_');
    try {
      final fragments = await IsochronProcessor.process(
        text: text,
        audioPath: audioPath,
        workDir: workDir,
        audioDriver: MacAudioDriver(),
        hasIds: effectiveHasIds,
        languageCode: languageCode,
        leadInSeconds: leadInSeconds,
        starScore: starScore,
        starPlacement: starPlacement,
        modelPath: modelPath,
        modelVariant: modelVariant,
        snapToPauses: snapPauses,
        onProgress: (status, pct) {
          if (verbose) {
            stdout.write('\r[${(pct * 100).toStringAsFixed(0)}%] $status');
          }
        },
      );
      if (verbose) stdout.writeln();

      final outputFile = File(effectiveOutputPath);
      final payload = TimingExport.exportPayload(
        fragments: fragments,
        format: effectiveFormat,
        sourceTextPath: textPath,
        requireIds: requireIds,
      );
      await outputFile.writeAsString(payload);
      print('Saved output to: ${outputFile.path}');
    } finally {
      if (await workDir.exists()) {
        await workDir.delete(recursive: true);
      }
    }
  } catch (e) {
    stderr.writeln('Error: $e');
    exit(1);
  }
}

Future<void> _handleEval(List<String> args) async {
  final parser = ArgParser()
    ..addOption('fixtures', abbr: 'f', defaultsTo: 'fixtures', help: 'Path to fixtures directory')
    ..addOption('csv', help: 'Optional output CSV file path')
    ..addOption('lead-in', defaultsTo: '0.19', help: 'Lead-in in seconds (default 0.19)')
    ..addOption('star-score', defaultsTo: '-2.0', help: 'Wildcard star token log-probability (default -2.0)')
    ..addOption('star-placement', allowed: ['segment', 'edges'], defaultsTo: 'segment')
    ..addOption('model-variant', allowed: ['int8', 'fp16', 'fp32'], defaultsTo: 'int8')
    ..addFlag('snap-pauses', help: 'Snap boundaries to qualifying acoustic pauses', defaultsTo: true)
    ..addFlag('help', abbr: 'h', negatable: false);

  final results = parser.parse(args);
  if (results['help'] as bool) {
    print('Usage: isochron eval [options]');
    print(parser.usage);
    exit(0);
  }

  final fixturesPath = results['fixtures'] as String;
  final fixturesDir = Directory(fixturesPath);
  if (!fixturesDir.existsSync()) {
    stderr.writeln('Error: Fixtures directory not found: $fixturesPath');
    exit(1);
  }

  final leadIn = double.tryParse(results['lead-in'] ?? '0.19') ?? 0.19;
  final starScore = double.tryParse(results['star-score'] ?? '-2.0') ?? -2.0;
  final starPlacement = results['star-placement'] == 'edges'
      ? StarPlacement.edges
      : StarPlacement.segment;
  final variantStr = results['model-variant'] as String? ?? 'int8';
  final variant = ModelVariant.values.firstWhere(
    (v) => v.name == variantStr,
    orElse: () => ModelVariant.int8,
  );
  final snapPauses = results['snap-pauses'] as bool;

  final evaluator = Evaluator();
  stdout.writeln('Running evaluation on fixtures in: ${fixturesDir.path}');

  final agg = await evaluator.evaluateDirectory(
    fixturesDir,
    mmsOptions: MmsPipelineOptions(
      leadInSeconds: leadIn,
      starScore: starScore,
      starPlacement: starPlacement,
      modelVariant: variant,
      snapToPauses: snapPauses,
    ),
    onProgress: (fixture, pct) {
      stdout.write('\r[${(pct * 100).toStringAsFixed(0)}%] Evaluating: $fixture...   ');
    },
  );
  stdout.writeln();

  final report = Evaluator.formatReport(agg);
  stdout.write(report);

  final csvPath = results['csv'] as String?;
  if (csvPath != null) {
    final csvFile = File(csvPath);
    await Evaluator.exportCsv(agg, csvFile);
    stdout.writeln('Exported CSV metrics to: ${csvFile.path}');
  }
}

Future<void> _handleModel(List<String> args) async {
  final parser = ArgParser()
    ..addOption('variant', allowed: ['int8', 'fp16', 'fp32'], defaultsTo: 'int8')
    ..addFlag('help', abbr: 'h', negatable: false);

  if (args.isEmpty || args.contains('-h') || args.contains('--help')) {
    print('Usage: isochron model <status|download|delete> [--variant int8|fp16|fp32]');
    exit(0);
  }

  final command = args.first;
  final results = parser.parse(args.sublist(1));

  final variantStr = results['variant'] as String? ?? 'int8';
  final variant = ModelVariant.values.firstWhere(
    (v) => v.name == variantStr,
    orElse: () => ModelVariant.int8,
  );

  final manager = ModelManager();

  switch (command) {
    case 'status':
      final status = await manager.checkStatus(variant, verifySha: true);
      final file = manager.getFile(variant);
      print('Model: ${variant.filename}');
      print('Path:   ${file.path}');
      print('Status: ${status.name}');
      if (status == ModelStatus.ready) {
        print('Size:   ${(variant.sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB');
      }
      break;

    case 'download':
      print('Downloading ${variant.filename}...');
      final file = await manager.download(
        variant,
        onProgress: (pct, rec, total) {
          final mbRec = (rec / 1024 / 1024).toStringAsFixed(1);
          final mbTot = (total / 1024 / 1024).toStringAsFixed(1);
          stdout.write('\r[${(pct * 100).toStringAsFixed(1)}%] $mbRec / $mbTot MB');
        },
      );
      print('\nDownloaded and verified: ${file.path}');
      break;

    case 'delete':
      await manager.delete(variant);
      print('Deleted ${variant.filename}');
      break;

    default:
      stderr.writeln('Unknown model command: $command');
      exit(1);
  }
}
