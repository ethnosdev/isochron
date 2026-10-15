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
