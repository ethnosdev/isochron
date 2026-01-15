import 'dart:io';
import 'package:path/path.dart' as p;
import '../core/fragment.dart';
import '../audio/wav_utils.dart';

class AnchorGenerator {
  final String binaryPath;
  AnchorGenerator({this.binaryPath = 'espeak-ng'});

  /// Generates the "Anchor" audio file (Synthetic TTS).
  /// Updates the [fragments] with the precise start/end times of the synthetic speech.
  /// Returns the path to the fully concatenated anchor file.
  Future<File> generate(List<Fragment> fragments, Directory workDir) async {
    final List<File> tempFiles = [];
    double currentTime = 0.0;

    // 1. Generate individual clips
    for (final frag in fragments) {
      final rawWavPath = p.join(workDir.path, 'frag_raw_${frag.index}.wav');
      final cleanWavPath = p.join(workDir.path, 'frag_${frag.index}.wav');

      // A. Call eSpeak-ng
      // -w: Write to file
      await Process.run(binaryPath, [
        '-w',
        rawWavPath,
        frag.text,
      ]);

      // B. Normalize using FFmpeg (Essential for correct duration math)
      // -ac 1: Mono
      // -ar 16000: 16kHz Sample Rate
      // -acodec pcm_s16le: 16-bit PCM
      await Process.run('ffmpeg', [
        '-y', // Overwrite if exists
        '-i', rawWavPath,
        '-ac', '1',
        '-ar', '16000',
        '-f', 'wav',
        '-acodec', 'pcm_s16le',
        cleanWavPath
      ]);

      final cleanFile = File(cleanWavPath);

      // C. Measure Duration
      final duration = await WavUtils.getDuration(cleanFile);

      // D. Update Fragment
      frag.setAnchorTiming(start: currentTime, end: currentTime + duration);

      // E. Advance Time
      currentTime += duration;
      tempFiles.add(cleanFile);

      // Cleanup raw file
      File(rawWavPath).delete().ignore();
    }

    // 2. Concatenate clips
    final concatListPath = p.join(workDir.path, 'concat_list.txt');
    final concatFile = File(concatListPath);
    final sink = concatFile.openWrite();

    for (final f in tempFiles) {
      // FFmpeg concat format: file '/path/to/file'
      sink.writeln("file '${f.path}'");
    }
    await sink.close();

    final fullAnchorPath = p.join(workDir.path, 'anchor_full.wav');

    await Process.run('ffmpeg', [
      '-y',
      '-f', 'concat',
      '-safe', '0',
      '-i', concatListPath,
      '-c', 'copy', // Copy codec (fast, no re-encoding)
      fullAnchorPath
    ]);

    return File(fullAnchorPath);
  }
}

extension IgnoreFuture on Future {
  void ignore() {}
}
