import 'dart:convert';
import 'dart:io';
import 'package:isochron_cli/src/core/text_parser.dart';
import 'package:isochron_cli/src/mms/mms_pipeline.dart';

Future<void> main(List<String> args) async {
  final fixtureName = args.isNotEmpty ? args.first : 'greek_matthew_1';
  final fixtureDir = Directory('fixtures/$fixtureName');
  if (!fixtureDir.existsSync()) {
    stdout.writeln('Fixture directory not found: ${fixtureDir.path}');
    return;
  }

  final audioFile = File('${fixtureDir.path}/audio.mp3');
  final textFile = File('${fixtureDir.path}/text.txt');
  final truthFile = File('${fixtureDir.path}/truth.json');
  final manifestFile = File('${fixtureDir.path}/manifest.json');

  final manifest = jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
  final lang = manifest['languageCode'] as String?;
  final hasIds = manifest['hasIds'] as bool? ?? false;

  final rawText = await textFile.readAsString();
  final fragments = TextParser.parse(rawText, hasIds: hasIds);
  final truthJson = jsonDecode(await truthFile.readAsString()) as List;

  stdout.writeln('=== Verifying Fixture: $fixtureName ===');
  stdout.writeln('Audio: ${audioFile.path}');
  stdout.writeln('Verses: ${fragments.length}');
  stdout.writeln('Language: $lang, hasIds: $hasIds');

  final pipeline = MmsPipeline();
  final stopwatch = Stopwatch()..start();

  final result = await pipeline.process(
    fragments: fragments,
    audioPath: audioFile.path,
    options: MmsPipelineOptions(
      languageCode: lang,
    ),
    onProgress: (stage, pct) {
      stdout.write('\r[Progress ${(pct * 100).toStringAsFixed(0)}%] $stage');
    },
  );
  stopwatch.stop();
  stdout.writeln('\n\nAlignment completed in ${stopwatch.elapsedMilliseconds} ms!');
  stdout.writeln('Stage timings: ${result.stageDurationsMs}');

  stdout.writeln('\n--- First 10 Verses: Predicted vs Truth ---');
  for (var i = 0; i < 10 && i < result.fragments.length; i++) {
    final pred = result.fragments[i];
    final truth = truthJson[i] as Map<String, dynamic>;
    final truthStart = (truth['start'] as num).toDouble();
    final truthEnd = (truth['end'] as num).toDouble();
    final error = pred.realStart - truthStart;

    stdout.writeln(
      'Verse $i: Pred: [${pred.realStart.toStringAsFixed(3)} .. ${pred.realEnd.toStringAsFixed(3)}] | '
      'Truth: [${truthStart.toStringAsFixed(3)} .. ${truthEnd.toStringAsFixed(3)}] | '
      'Diff: ${error >= 0 ? '+' : ''}${error.toStringAsFixed(3)} s',
    );
  }
}
