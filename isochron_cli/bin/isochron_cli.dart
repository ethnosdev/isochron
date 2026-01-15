import 'dart:io';
import 'package:args/args.dart';

void main(List<String> arguments) {
  final parser = ArgParser()
    ..addOption('text', abbr: 't', help: 'Path to the input text file')
    ..addOption('audio', abbr: 'a', help: 'Path to the input audio file')
    ..addOption(
      'output',
      abbr: 'o',
      help: 'Path to save the alignment JSON',
      defaultsTo: 'alignment.json',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      help: 'Show detailed logs',
      defaultsTo: false,
    )
    ..addFlag(
      'help',
      abbr: 'h',
      help: 'Show usage information',
      negatable: false,
    );

  try {
    final results = parser.parse(arguments);

    if (results['help'] as bool) {
      print('Isochron - a synthesis-based forced aligner');
      print(parser.usage);
      exit(0);
    }

    final textPath = results['text'];
    final audioPath = results['audio'];

    if (textPath == null || audioPath == null) {
      stderr.writeln('Error: Both --text and --audio are required.');
      print(parser.usage);
      exit(1);
    }

    print('Isochron CLI started...');
    print('Text file: $textPath');
    print('Audio file: $audioPath');

    // Future pipeline:
    // 1. Text Parser -> List<Fragment>
    // 2. AnchorGenerator (eSpeak) -> anchor.wav + timestamps
    // 3. AudioProcessor (FFmpeg) -> user_mono_16k.wav
    // 4. MFCCExtractor (Isolate) -> List<List<double>> (for both files)
    // 5. DTWAligner (Isolate) -> Alignment Path
    // 6. Project timestamps -> JSON Output
  } catch (e) {
    stderr.writeln('Error: $e');
    exit(1);
  }
}
