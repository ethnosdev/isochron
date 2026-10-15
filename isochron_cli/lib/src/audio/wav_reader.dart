import 'dart:io';
import 'dart:typed_data';

class AudioData {
  final Float32List samples;
  final int sampleRate;
  final int channels;
  final double durationSeconds;

  const AudioData({
    required this.samples,
    required this.sampleRate,
    required this.channels,
    required this.durationSeconds,
  });
}

class WavReader {
  /// Reads a 16-bit PCM mono or stereo WAV file into float32 samples.
  /// If [enforceMono16k] is true, throws if the audio is not 16kHz mono.
  static Future<AudioData> read(File file, {bool enforceMono16k = true}) async {
    final bytes = await file.readAsBytes();
    return readFromBytes(bytes, enforceMono16k: enforceMono16k);
  }

  static AudioData readFromBytes(Uint8List bytes, {bool enforceMono16k = true}) {
    if (bytes.length < 12) {
      throw const FormatException('Invalid WAV file: header too short');
    }

    final byteData = ByteData.sublistView(bytes);

    // Verify RIFF / WAVE
    final riff = String.fromCharCodes(bytes.sublist(0, 4));
    final wave = String.fromCharCodes(bytes.sublist(8, 12));
    if (riff != 'RIFF' || wave != 'WAVE') {
      throw FormatException('Not a valid RIFF/WAVE file: $riff / $wave');
    }

    int audioFormat = 0;
    int numChannels = 0;
    int sampleRate = 0;
    int bitsPerSample = 0;

    int? dataOffset;
    int? dataSize;

    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = byteData.getUint32(offset + 4, Endian.little);
      offset += 8;

      if (chunkId == 'fmt ') {
        if (chunkSize < 16) {
          throw const FormatException('Invalid fmt chunk size');
        }
        audioFormat = byteData.getUint16(offset, Endian.little);
        numChannels = byteData.getUint16(offset + 2, Endian.little);
        sampleRate = byteData.getUint32(offset + 4, Endian.little);
        bitsPerSample = byteData.getUint16(offset + 14, Endian.little);
      } else if (chunkId == 'data') {
        dataOffset = offset;
        dataSize = chunkSize;
      }

      offset += chunkSize;
      if (chunkSize.isOdd) {
        offset += 1; // RIFF chunks are padded to 2-byte boundaries
      }
    }

    if (dataOffset == null || dataSize == null) {
      throw const FormatException('Missing data chunk in WAV file');
    }

    if (enforceMono16k) {
      if (sampleRate != 16000) {
        throw FormatException('Expected 16000 Hz, got $sampleRate Hz');
      }
      if (numChannels != 1) {
        throw FormatException('Expected mono (1 channel), got $numChannels channels');
      }
    }

    if (audioFormat != 1 && audioFormat != 3) {
      throw FormatException('Unsupported audio format: $audioFormat (only PCM=1 and Float=3 supported)');
    }

    final end = (dataOffset + dataSize).clamp(0, bytes.length);
    final rawData = bytes.sublist(dataOffset, end);
    final rawDataView = ByteData.sublistView(rawData);

    Float32List floatSamples;

    if (audioFormat == 1 && bitsPerSample == 16) {
      final sampleCount = rawData.length ~/ 2;
      floatSamples = Float32List(sampleCount);
      for (var i = 0; i < sampleCount; i++) {
        final int16Sample = rawDataView.getInt16(i * 2, Endian.little);
        floatSamples[i] = int16Sample / 32768.0;
      }
    } else if (audioFormat == 3 && bitsPerSample == 32) {
      final sampleCount = rawData.length ~/ 4;
      floatSamples = Float32List(sampleCount);
      for (var i = 0; i < sampleCount; i++) {
        floatSamples[i] = rawDataView.getFloat32(i * 4, Endian.little);
      }
    } else if (audioFormat == 1 && bitsPerSample == 8) {
      final sampleCount = rawData.length;
      floatSamples = Float32List(sampleCount);
      for (var i = 0; i < sampleCount; i++) {
        final u8 = rawData[i];
        floatSamples[i] = (u8 - 128) / 128.0;
      }
    } else {
      throw FormatException('Unsupported bit depth: $bitsPerSample-bit for format $audioFormat');
    }

    final duration = floatSamples.length / (sampleRate * numChannels);

    return AudioData(
      samples: floatSamples,
      sampleRate: sampleRate,
      channels: numChannels,
      durationSeconds: duration,
    );
  }
}
