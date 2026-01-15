import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:isochron_cli/isochron_cli.dart';

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('text', abbr: 't', help: 'Path to the input text file')
    ..addOption('audio', abbr: 'a', help: 'Path to the input audio file')
    ..addOption('output',
        abbr: 'o',
        help: 'Path to save the alignment JSON',
        defaultsTo: 'alignment.json')
    ..addFlag('verbose',
        abbr: 'v', help: 'Show detailed logs', defaultsTo: false)
    ..addFlag('help',
        abbr: 'h', help: 'Show usage information', negatable: false);

  try {
    final results = parser.parse(arguments);

    if (results['help'] as bool) {
      print('Isochron - a synthesis-based forced aligner');
      print(parser.usage);
      exit(0);
    }

    final textPath = results['text'];
    final audioPath = results['audio'];
    final outputJsonPath = results['output'] ?? 'alignment.json';
    final verbose = results['verbose'] as bool;

    if (textPath == null || audioPath == null) {
      stderr.writeln('Error: Both --text and --audio are required.');
      print(parser.usage);
      exit(1);
    }

    // --- Setup Workspace ---
    final workDir = Directory.systemTemp.createTempSync('isochron_run_');
    if (verbose) print('Workspace: ${workDir.path}');

    try {
      // 1. Text Parsing
      if (verbose) print('[1/6] Parsing text...');
      final textFile = File(textPath);
      final rawText = await textFile.readAsString();
      final fragments = TextParser.parse(rawText);
      if (verbose) print('      Found ${fragments.length} fragments.');

      // 2. Anchor Generation
      if (verbose) print('[2/6] Generating anchor audio (eSpeak)...');
      final anchorGen = AnchorGenerator();
      final anchorFile = await anchorGen.generate(fragments, workDir);
      if (verbose)
        print(
            '      Anchor generated: ${await WavUtils.getDuration(anchorFile)}s');

      // 3. Audio Normalization (User Audio)
      if (verbose) print('[3/6] Normalizing user audio (FFmpeg)...');
      final userAudioRaw = File(audioPath);
      final userAudioWav = File(p.join(workDir.path, 'user_mono_16k.wav'));

      // FFmpeg command to convert user audio to 16k mono 16-bit
      await Process.run('ffmpeg', [
        '-y',
        '-i',
        userAudioRaw.path,
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

      if (!userAudioWav.existsSync()) {
        throw Exception('Failed to convert user audio using FFmpeg.');
      }

      // 4. Feature Extraction
      if (verbose) print('[4/6] Extracting MFCCs...');

      // Helper to read bytes safely skipping header
      Float64List readWavData(File f) {
        final bytes = f.readAsBytesSync();
        // Skip 44 byte header, view as Int16, convert to double
        final int16Data = bytes.buffer.asInt16List(44);
        final floatData = Float64List(int16Data.length);
        for (int i = 0; i < int16Data.length; i++) {
          // Normalize Int16 to -1.0..1.0
          floatData[i] = int16Data[i] / 32768.0;
        }
        return floatData;
      }

      final anchorData = readWavData(anchorFile);
      final userData = readWavData(userAudioWav);

      if (verbose) print('      Computing Anchor MFCCs...');
      final anchorMfcc = MfccExtractor.extract(anchorData);

      if (verbose) print('      Computing User MFCCs...');
      final userMfcc = MfccExtractor.extract(userData);

      // 5. Alignment (DTW)
      if (verbose)
        print(
            '[5/6] Aligning (${anchorMfcc.length} x ${userMfcc.length} frames)...');
      // Use Isolates in a real production app here. For CLI v1, sync is okay.
      final path = DtwAligner.align(userMfcc, anchorMfcc);
      if (verbose) print('      Alignment path length: ${path.length}');

      // 6. Projection
      if (verbose) print('[6/6] Projecting timestamps...');
      TimeProjector.project(fragments, path);

      // 7. Output
      final jsonOutput = fragments
          .map((f) => {
                'id': f.index,
                'text': f.text,
                'start': double.parse(f.realStart.toStringAsFixed(3)),
                'end': double.parse(f.realEnd.toStringAsFixed(3)),
              })
          .toList();

      final jsonFile = File(outputJsonPath);
      await jsonFile.writeAsString(jsonEncode(jsonOutput));

      print('Success! Alignment saved to: $outputJsonPath');
    } catch (e, stack) {
      stderr.writeln('Critical Error: $e');
      if (verbose) stderr.writeln(stack);
      exit(1);
    } finally {
      // Cleanup
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
