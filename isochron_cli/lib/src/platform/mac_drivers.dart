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
    // Directly synthesize to 16kHz mono WAV using macOS `say`
    final sayResult = await Process.run('/usr/bin/say', [
      '-v',
      'Samantha',
      '--file-format=WAVE',
      '--data-format=LEI16@16000',
      '-o',
      outputPath,
      text,
    ]);

    if (sayResult.exitCode != 0) {
      throw Exception("macOS 'say' failed: ${sayResult.stderr}");
    }
  }
}
