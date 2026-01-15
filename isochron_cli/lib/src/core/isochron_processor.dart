import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import '../core/fragment.dart';
import '../core/text_parser.dart';
import '../core/time_projector.dart';
import '../synthesis/anchor_generator.dart';
import '../audio/wav_utils.dart';
import '../math/mfcc_extractor.dart';
import '../math/dtw_aligner.dart';
import 'transliterator.dart';

class IsochronProcessor {
  /// Runs the full alignment pipeline.
  ///
  /// [workDir]: Temporary directory for intermediate files.
  /// [ffmpegPath]: Path or command for FFmpeg (default 'ffmpeg').
  /// [espeakPath]: Path or command for eSpeak (default 'espeak-ng').
  static Future<List<Fragment>> process({
    required String text,
    required String audioPath,
    required Directory workDir,
    String ffmpegPath = 'ffmpeg',
    String espeakPath = 'espeak-ng',
    Map<String, String>? transliterationRules,
  }) async {
    // 1. Parse Text
    final fragments = TextParser.parse(text);
    if (fragments.isEmpty) throw Exception("No text found in file.");

    // Apply rules if they exist
    if (transliterationRules != null && transliterationRules.isNotEmpty) {
      for (final frag in fragments) {
        frag.spokenText =
            Transliterator.convert(frag.text, transliterationRules);
      }
    }

    // 2. Generate Anchor (Pass custom binary path)
    final anchorGen = AnchorGenerator(binaryPath: espeakPath);
    final anchorFile = await anchorGen.generate(fragments, workDir);

    // 3. Normalize User Audio (Pass custom binary path)
    final userAudioWav = File(p.join(workDir.path, 'user_mono_16k.wav'));

    // We execute FFmpeg manually here to ensure we use the dynamic path
    final result = await Process.run(ffmpegPath, [
      '-y',
      '-i',
      audioPath,
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

    if (result.exitCode != 0) {
      throw Exception('FFmpeg failed: ${result.stderr}');
    }

    // 4. Feature Extraction
    final anchorMfcc = MfccExtractor.extract(_readWavData(anchorFile));
    final userMfcc = MfccExtractor.extract(_readWavData(userAudioWav));

    // 5. Alignment
    final path = DtwAligner.align(userMfcc, anchorMfcc);

    // 6. Projection
    TimeProjector.project(fragments, path);

    return fragments;
  }

  // Helper to read WAV bytes safely
  static Float64List _readWavData(File f) {
    final bytes = f.readAsBytesSync();
    // Skip 44 byte header, view as Int16, convert to double
    if (bytes.length < 44) return Float64List(0);
    final int16Data = bytes.buffer.asInt16List(44);
    final floatData = Float64List(int16Data.length);
    for (int i = 0; i < int16Data.length; i++) {
      floatData[i] = int16Data[i] / 32768.0;
    }
    return floatData;
  }
}
