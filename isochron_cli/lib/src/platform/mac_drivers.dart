import 'dart:io';
import '../core/drivers.dart';
import '../audio/wav_utils.dart';

class MacAudioDriver implements AudioDriver {
  @override
  Future<void> normalize(String inputPath, String outputPath) async {
    final result = await Process.run('/usr/bin/afconvert',
        ['-f', 'WAVE', '-d', 'LEI16@16000', '-c', '1', inputPath, outputPath]);

    if (result.exitCode != 0) {
      throw Exception('macOS afconvert failed: ${result.stderr}');
    }
  }

  @override
  Future<void> concatenate(List<File> files, File output) async {
    await WavUtils.concatenate(files, output);
  }
}

class MacTtsDriver implements TtsDriver {
  @override
  Future<void> synthesize(String text, String outputPath) async {
    final tempAiff = outputPath.replaceAll('.wav', '.aiff');

    // 1. Synthesize to high-quality AIFF using macOS `say`
    final sayResult = await Process.run('/usr/bin/say', [
      '-v',
      'Samantha',
      '-o',
      tempAiff,
      text,
    ]);

    if (sayResult.exitCode != 0) {
      throw Exception("macOS 'say' failed: ${sayResult.stderr}");
    }

    // 2. Normalize to strict 16kHz WAV using afconvert
    final afResult = await Process.run('/usr/bin/afconvert',
        ['-f', 'WAVE', '-d', 'LEI16@16000', '-c', '1', tempAiff, outputPath]);

    if (afResult.exitCode != 0) {
      throw Exception("macOS TTS afconvert failed: ${afResult.stderr}");
    }

    // Cleanup the temp AIFF file
    File(tempAiff).deleteSync();
  }
}
