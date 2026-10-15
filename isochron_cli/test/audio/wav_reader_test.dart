import 'dart:typed_data';
import 'package:isochron_cli/src/audio/wav_reader.dart';
import 'package:test/test.dart';

void main() {
  group('WavReader', () {
    test('parses synthetic 16kHz mono 16-bit PCM WAV', () {
      final sampleRate = 16000;
      final numSamples = 1600; // 0.1s
      final pcmBytes = ByteData(numSamples * 2);
      for (var i = 0; i < numSamples; i++) {
        // Half-scale positive sample: 16384 -> ~0.5
        pcmBytes.setInt16(i * 2, 16384, Endian.little);
      }

      final header = ByteData(44);
      // RIFF
      header.setUint8(0, 0x52); // R
      header.setUint8(1, 0x49); // I
      header.setUint8(2, 0x46); // F
      header.setUint8(3, 0x46); // F
      header.setUint32(4, 36 + pcmBytes.lengthInBytes, Endian.little);
      // WAVE
      header.setUint8(8, 0x57);  // W
      header.setUint8(9, 0x41);  // A
      header.setUint8(10, 0x56); // V
      header.setUint8(11, 0x45); // E
      // fmt
      header.setUint8(12, 0x66); // f
      header.setUint8(13, 0x6d); // m
      header.setUint8(14, 0x74); // t
      header.setUint8(15, 0x20); // ' '
      header.setUint32(16, 16, Endian.little); // chunk size
      header.setUint16(20, 1, Endian.little);  // PCM
      header.setUint16(22, 1, Endian.little);  // 1 channel
      header.setUint32(24, sampleRate, Endian.little);
      header.setUint32(28, sampleRate * 2, Endian.little); // byte rate
      header.setUint16(32, 2, Endian.little);  // block align
      header.setUint16(34, 16, Endian.little); // bits per sample
      // data
      header.setUint8(36, 0x64); // d
      header.setUint8(37, 0x61); // a
      header.setUint8(38, 0x74); // t
      header.setUint8(39, 0x61); // a
      header.setUint32(40, pcmBytes.lengthInBytes, Endian.little);

      final fullBytes = Uint8List(44 + pcmBytes.lengthInBytes);
      fullBytes.setRange(0, 44, header.buffer.asUint8List());
      fullBytes.setRange(44, fullBytes.length, pcmBytes.buffer.asUint8List());

      final audio = WavReader.readFromBytes(fullBytes);
      expect(audio.sampleRate, equals(16000));
      expect(audio.channels, equals(1));
      expect(audio.durationSeconds, closeTo(0.1, 0.001));
      expect(audio.samples.length, equals(1600));
      expect(audio.samples[0], closeTo(0.5, 0.001));
    });

    test('throws on non-WAV data', () {
      expect(
        () => WavReader.readFromBytes(Uint8List(20)),
        throwsFormatException,
      );
    });

    test('throws on incorrect sample rate when enforced', () {
      final header = ByteData(44);
      header.setUint8(0, 0x52);
      header.setUint8(1, 0x49);
      header.setUint8(2, 0x46);
      header.setUint8(3, 0x46);
      header.setUint32(4, 36, Endian.little);
      header.setUint8(8, 0x57);
      header.setUint8(9, 0x41);
      header.setUint8(10, 0x56);
      header.setUint8(11, 0x45);
      header.setUint8(12, 0x66);
      header.setUint8(13, 0x6d);
      header.setUint8(14, 0x74);
      header.setUint8(15, 0x20);
      header.setUint32(16, 16, Endian.little);
      header.setUint16(20, 1, Endian.little);
      header.setUint16(22, 1, Endian.little);
      header.setUint32(24, 44100, Endian.little); // 44.1kHz
      header.setUint32(28, 44100 * 2, Endian.little);
      header.setUint16(32, 2, Endian.little);
      header.setUint16(34, 16, Endian.little);
      header.setUint8(36, 0x64);
      header.setUint8(37, 0x61);
      header.setUint8(38, 0x74);
      header.setUint8(39, 0x61);
      header.setUint32(40, 0, Endian.little);

      expect(
        () => WavReader.readFromBytes(header.buffer.asUint8List(), enforceMono16k: true),
        throwsFormatException,
      );
    });
  });
}
