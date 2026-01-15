import 'dart:io';
import 'dart:typed_data';

class WavUtils {
  /// Calculates the duration of a WAV file in seconds.
  /// Assumes standard RIFF WAV format.
  static Future<double> getDuration(File file) async {
    final length = await file.length();

    // Standard WAV header is 44 bytes.
    // However, we shouldn't guess the sample rate. We should read it.
    // For this Clean Room implementation, to keep it simple,
    // we will enforce a standard format (16kHz, Mono, 16-bit) via FFmpeg later.
    //
    // If we assume 16kHz, 1 channel, 16-bit (2 bytes per sample):
    // Bytes per second = 16000 * 1 * 2 = 32000.

    const int headerSize = 44;
    const int sampleRate = 16000;
    const int numChannels = 1;
    const int bytesPerSample = 2; // 16-bit

    if (length < headerSize) return 0.0;

    final dataSize = length - headerSize;
    final bytesPerSecond = sampleRate * numChannels * bytesPerSample;

    return dataSize / bytesPerSecond;
  }
}
