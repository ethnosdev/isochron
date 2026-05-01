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
    // we will enforce a standard format (16kHz, Mono, 16-bit) later.
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

  /// Concatenates multiple WAV files into a single WAV file purely in Dart.
  static Future<File> concatenate(List<File> files, File output) async {
    if (files.isEmpty) throw Exception("No files to concatenate.");

    final builder = BytesBuilder();
    int totalDataLen = 0;

    // Reserve 44 bytes at the start for the new header
    builder.add(Uint8List(44));

    for (var file in files) {
      final bytes = await file.readAsBytes();
      if (bytes.length <= 44) continue; // Skip empty/invalid files

      // Skip the 44-byte header, grab the raw audio data
      final dataBytes = bytes.sublist(44);
      builder.add(dataBytes);
      totalDataLen += dataBytes.length;
    }

    // Grab a valid header from the first file to use as a template
    final firstFileBytes = await files.first.readAsBytes();
    final header = firstFileBytes.sublist(0, 44);

    // Create a ByteData view to easily rewrite the 32-bit integer sizes
    final byteData = ByteData.view(header.buffer);

    // Offset 4: RIFF chunk size (36 + data size)
    byteData.setUint32(4, 36 + totalDataLen, Endian.little);

    // Offset 40: Data chunk size
    byteData.setUint32(40, totalDataLen, Endian.little);

    // Combine the corrected header with our merged audio data
    final finalBytes = builder.toBytes();
    finalBytes.setRange(0, 44, header);

    await output.writeAsBytes(finalBytes);
    return output;
  }
}
