import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'package:isochron_cli/isochron_cli.dart';

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('text', abbr: 't', help: 'Path to the input text file')
    ..addOption('audio', abbr: 'a', help: 'Path to the input audio file')
    ..addOption('output',
        abbr: 'o',
        help: 'Path to save the alignment JSON',
        defaultsTo: 'alignment.json')
    ..addOption('ffmpeg', help: 'Path to ffmpeg binary', defaultsTo: 'ffmpeg')
    ..addOption('espeak',
        help: 'Path to espeak-ng binary', defaultsTo: 'espeak-ng')
    ..addOption('dict',
        help: 'Path to a JSON file containing transliteration rules')
    ..addFlag('verbose',
        abbr: 'v', help: 'Show detailed logs', defaultsTo: false)
    ..addFlag('help',
        abbr: 'h', help: 'Show usage information', negatable: false);

  try {
    final results = parser.parse(arguments);

    if (results['help'] as bool) {
      print('Isochron Aligner - Clean Room Implementation');
      print(parser.usage);
      exit(0);
    }

    final textPath = results['text'];
    final audioPath = results['audio'];
    final dictPath = results['dict'];
    final outputJsonPath = results['output'];
    final ffmpegPath = results['ffmpeg'];
    final espeakPath = results['espeak'];
    // final transliterate = results['transliterate'] as bool;
    final verbose = results['verbose'] as bool;
    Map<String, String>? rules;

    if (textPath == null || audioPath == null) {
      stderr.writeln('Error: Both --text and --audio are required.');
      print(parser.usage);
      exit(1);
    }

    if (dictPath != null) {
      if (verbose) print('Loading transliteration rules from: $dictPath');
      final dictFile = File(dictPath);
      if (!dictFile.existsSync()) {
        stderr.writeln("Error: Dictionary file not found.");
        exit(1);
      }

      final jsonString = await dictFile.readAsString();
      try {
        // Decode JSON to Map<String, dynamic>, then cast to Map<String, String>
        final rawMap = jsonDecode(jsonString) as Map<String, dynamic>;
        rules = rawMap.map((key, value) => MapEntry(key, value.toString()));
      } catch (e) {
        stderr.writeln("Error: Invalid JSON format in dictionary file.");
        exit(1);
      }
    }

    // --- Setup Workspace ---
    final workDir = Directory.systemTemp.createTempSync('isochron_cli_');
    if (verbose) print('Workspace: ${workDir.path}');

    try {
      if (verbose) print('Starting alignment pipeline...');
      final textFile = File(textPath);
      final rawText = await textFile.readAsString();

      // --- RUN PROCESSOR ---
      final fragments = await IsochronProcessor.process(
        text: rawText,
        audioPath: audioPath,
        workDir: workDir,
        ffmpegPath: ffmpegPath,
        espeakPath: espeakPath,
        transliterationRules: rules,
      );
      // ---------------------

      if (verbose) {
        print('Alignment complete. Found ${fragments.length} fragments.');
      }

      // Output Generation
      final jsonOutput = fragments
          .map((f) => {
                'index': f.index,
                if (f.id != null) 'id': f.id,
                'text': f.text,
                'start': double.parse(f.realStart.toStringAsFixed(3)),
                'end': double.parse(f.realEnd.toStringAsFixed(3)),
              })
          .toList();

      final jsonFile = File(outputJsonPath);
      await jsonFile.writeAsString(jsonEncode(jsonOutput));

      print('Success! Saved to: $outputJsonPath');
    } catch (e, stack) {
      stderr.writeln('Critical Error: $e');
      if (verbose) stderr.writeln(stack);
      exit(1);
    } finally {
      if (!verbose) {
        workDir.deleteSync(recursive: true);
      } else {
        print('Debug: Temp files left in ${workDir.path}');
      }
    }
  } catch (e) {
    stderr.writeln('Error: $e');
    exit(1);
  }
}
