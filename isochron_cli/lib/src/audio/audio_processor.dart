// import 'dart:io';

// class AudioProcessor {
//   final String binaryPath;
//   AudioProcessor({this.binaryPath = 'ffmpeg'});

//   Future<void> convertTo16k(File input, File output) async {
//     await Process.run(binaryPath, [
//       '-y', '-i', input.path,
//       '-ac', '1', '-ar', '16000', '-f', 'wav', '-acodec', 'pcm_s16le',
//       output.path
//     ]);
//   }
// }
