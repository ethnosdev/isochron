import 'dart:io';
import 'package:path/path.dart' as p;
import '../core/fragment.dart';
import '../core/drivers.dart';
import '../audio/wav_utils.dart';

class AnchorGenerator {
  final AudioDriver audioDriver;
  final TtsDriver ttsDriver;

  AnchorGenerator({required this.audioDriver, required this.ttsDriver});

  Future<File> generate(List<Fragment> fragments, Directory workDir) async {
    final List<File> tempFiles = [];
    double currentTime = 0.0;

    for (final frag in fragments) {
      final cleanWavPath = p.join(workDir.path, 'frag_${frag.index}.wav');
      final textToSpeak = frag.spokenText ?? frag.text;

      // 1. Synthesize Audio
      await ttsDriver.synthesize(textToSpeak, cleanWavPath);

      File cleanFile = File(cleanWavPath);

      // 2. Measure Duration
      final duration = await WavUtils.getDuration(cleanFile);

      // 3. Update Fragment Timings
      frag.setAnchorTiming(start: currentTime, end: currentTime + duration);
      currentTime += duration;
      tempFiles.add(cleanFile);
    }

    // 4. Concatenate clips
    final fullAnchorPath = p.join(workDir.path, 'anchor_full.wav');
    final anchorFile = File(fullAnchorPath);

    await audioDriver.concatenate(tempFiles, anchorFile);

    return anchorFile;
  }
}
