import 'dart:io';

/// Handles audio manipulation (normalization and concatenation).
abstract class AudioDriver {
  /// Converts ANY audio file into a 16kHz, Mono, 16-bit PCM WAV file.
  Future<void> normalize(String inputPath, String outputPath);

  /// Stitches multiple WAV files together end-to-end.
  Future<void> concatenate(List<File> files, File output);
}

/// Handles Text-To-Speech generation.
abstract class TtsDriver {
  /// Converts text into a 16kHz, Mono, 16-bit PCM WAV file.
  Future<void> synthesize(String text, String outputPath);
}
