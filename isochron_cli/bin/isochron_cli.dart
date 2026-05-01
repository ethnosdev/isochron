import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'package:isochron_cli/src/core/isochron_processor.dart';
import 'package:isochron_cli/src/core/drivers.dart';
import 'package:isochron_cli/src/platform/mac_drivers.dart';
import 'package:isochron_cli/src/core/boundary_strategy.dart';

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('text', abbr: 't', help: 'Path to the input text file')
    ..addOption('audio', abbr: 'a', help: 'Path to the input audio file')
    ..addOption('output',
        abbr: 'o',
        help: 'Path to save the alignment JSON',
        defaultsTo: 'alignment.json')
    ..addOption('dict',
        help: 'Path to a JSON file containing transliteration rules')
    ..addOption('pins',
        help:
            'Path to a JSON file containing known-correct timings for specific fragments. '
            'Keys are fragment indices (0-based strings), values are objects with "start" and "end" in seconds. '
            'Example: {"0":{"start":0.0,"end":1.4},"7":{"start":12.3,"end":15.2}}')
    ..addOption('snap-mode',
        allowed: ['onset', 'gap'],
        help: 'Controls how fragment boundaries are refined. '
            '"onset" snaps to the start of speech (legacy behaviour). '
            '"gap" snaps to the middle of the detected silence gap.',
        defaultsTo: 'onset')
    ..addOption(
      'snap-offset',
      help: 'Milliseconds subtracted from each onset-snapped phrase start '
          '(snap-mode onset only; default 0).',
    )
    ..addFlag('verbose',
        abbr: 'v', help: 'Show detailed logs', defaultsTo: false)
    ..addFlag('help',
        abbr: 'h', help: 'Show usage information', negatable: false);

  try {
    final results = parser.parse(arguments);

    if (results['help'] as bool) {
      print('Isochron Aligner - Native Cross-Platform Architecture');
      print(parser.usage);
      exit(0);
    }

    final textPath = results['text'];
    final audioPath = results['audio'];
    final dictPath = results['dict'];
    final pinsPath = results['pins'];
    final outputJsonPath = results['output'];
    final snapModeRaw = results['snap-mode'] as String? ?? 'onset';
    final snapOffsetRaw = results['snap-offset'] as String?;
    final verbose = results['verbose'] as bool;

    int snapOffsetMs = 0;
    if (snapOffsetRaw != null && snapOffsetRaw.trim().isNotEmpty) {
      final parsed = int.tryParse(snapOffsetRaw.trim());
      if (parsed == null) {
        stderr.writeln(
            'Error: --snap-offset must be a non-negative integer (milliseconds).');
        exit(1);
      }
      if (parsed < 0) {
        stderr.writeln('Error: --snap-offset must be >= 0.');
        exit(1);
      }
      snapOffsetMs = parsed;
    }

    Map<String, String>? rules;
    Map<int, ({double start, double end})>? pinnedTimings;

    if (textPath == null || audioPath == null) {
      stderr.writeln('Error: Both --text and --audio are required.');
      print(parser.usage);
      exit(1);
    }

    // --- Load Dictionary ---
    if (dictPath != null) {
      if (verbose) print('Loading transliteration rules from: $dictPath');
      final dictFile = File(dictPath);
      if (!dictFile.existsSync()) {
        stderr.writeln("Error: Dictionary file not found.");
        exit(1);
      }

      final jsonString = await dictFile.readAsString();
      try {
        final rawMap = jsonDecode(jsonString) as Map<String, dynamic>;
        rules = rawMap.map((key, value) => MapEntry(key, value.toString()));
      } catch (e) {
        stderr.writeln("Error: Invalid JSON format in dictionary file.");
        exit(1);
      }
    }

    // --- Load Pins ---
    if (pinsPath != null) {
      if (verbose) print('Loading pinned timings from: $pinsPath');
      final pinsFile = File(pinsPath);
      if (!pinsFile.existsSync()) {
        stderr.writeln('Error: Pins file not found: $pinsPath');
        exit(1);
      }
      try {
        final rawMap =
            jsonDecode(await pinsFile.readAsString()) as Map<String, dynamic>;
        pinnedTimings = {};
        for (final entry in rawMap.entries) {
          final idx = int.tryParse(entry.key);
          if (idx == null) {
            stderr.writeln(
                'Warning: Skipping invalid pin key "${entry.key}" (must be an integer index).');
            continue;
          }
          final obj = entry.value as Map<String, dynamic>;
          final start = (obj['start'] as num).toDouble();
          final end = (obj['end'] as num).toDouble();
          pinnedTimings[idx] = (start: start, end: end);
        }
        if (verbose) print('Loaded ${pinnedTimings.length} pinned timing(s).');
      } catch (e) {
        stderr.writeln('Error: Invalid JSON format in pins file: $e');
        exit(1);
      }
    }

    // --- OS DETECTION & DRIVER INJECTION ---
    late AudioDriver audioDriver;
    late TtsDriver ttsDriver;

    if (Platform.isMacOS) {
      if (verbose) print('OS Detected: macOS. Using native Apple frameworks.');
      audioDriver = MacAudioDriver();
      ttsDriver = MacTtsDriver();
    } else if (Platform.isWindows) {
      stderr.writeln(
          'Error: Windows is not yet supported natively. Implement WindowsDrivers first.');
      exit(1);
    } else if (Platform.isLinux) {
      stderr.writeln(
          'Error: Linux is not yet supported natively. Implement LinuxDrivers first.');
      exit(1);
    } else {
      stderr.writeln('Error: Unsupported Operating System.');
      exit(1);
    }

    // Map CLI option to SnapMode enum. Default is conservative: onset.
    final SnapMode snapMode =
        snapModeRaw == 'gap' ? SnapMode.gapCenter : SnapMode.onset;

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
        audioDriver: audioDriver,
        ttsDriver: ttsDriver,
        transliterationRules: rules,
        pinnedTimings: pinnedTimings,
        onProgress: verbose
            ? (status, pct) =>
                print('[${(pct * 100).toStringAsFixed(1)}%] $status')
            : null,
        snapMode: snapMode,
        snapOffsetMs: snapOffsetMs,
      );
      // ---------------------

      if (verbose) {
        print('Alignment complete. Found ${fragments.length} fragments.');
      }

      // --- Output Generation ---
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
