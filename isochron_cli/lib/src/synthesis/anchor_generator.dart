import 'dart:io';
import 'package:path/path.dart' as p;
import '../core/fragment.dart';
import '../core/drivers.dart';
import '../audio/wav_utils.dart';

class AnchorGenerator {
  final AudioDriver audioDriver;
  final TtsDriver ttsDriver;

  AnchorGenerator({required this.audioDriver, required this.ttsDriver});

  /// Generates synthetic audio for all fragments.
  /// [onProgress] receives a value from 0.0 to 1.0 representing completion percentage.
  Future<File> generate(List<Fragment> fragments, Directory workDir,
      {Function(double)? onProgress}) async {
    final List<({File file, Fragment frag})> tasks = [];
    for (final frag in fragments) {
      final cleanWavPath = p.join(workDir.path, 'frag_${frag.index}.wav');
      tasks.add((file: File(cleanWavPath), frag: frag));
    }

    // Run synthesis in batches to respect concurrency limits
    const concurrency = 4;
    final results = <({File file, Fragment frag, double duration})>[];
    int completedTasks = 0;

    for (var i = 0; i < tasks.length; i += concurrency) {
      final batch = tasks.skip(i).take(concurrency).toList();

      final batchResults = await Future.wait(batch.map((task) async {
        // Synthesize the text
        await ttsDriver.synthesize(
            task.frag.spokenText ?? task.frag.text, task.file.path);

        // Calculate duration for timing
        final duration = await WavUtils.getDuration(task.file);

        // Report progress increment
        completedTasks++;
        if (onProgress != null) {
          onProgress(completedTasks / tasks.length);
        }

        return (file: task.file, frag: task.frag, duration: duration);
      }));

      results.addAll(batchResults);
    }

    // Assign timings in original order
    double currentTime = 0.0;
    for (final r in results) {
      r.frag.setAnchorTiming(start: currentTime, end: currentTime + r.duration);
      currentTime += r.duration;
    }

    // Concatenate into final anchor file
    final tempFiles = results.map((r) => r.file).toList();
    final fullAnchorPath = p.join(workDir.path, 'anchor_full.wav');
    final anchorFile = File(fullAnchorPath);
    await audioDriver.concatenate(tempFiles, anchorFile);

    return anchorFile;
  }
}
