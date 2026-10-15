import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

const onnxVersion = '1.31.0';
const onnxArch = 'osx-arm64';
final onnxUrl = Uri.parse(
  'https://github.com/microsoft/onnxruntime/releases/download/v$onnxVersion/onnxruntime-$onnxArch-$onnxVersion.tgz',
);
const expectedSha256 =
    '1031b36dd3bdaa8d976a6130d9cf2a05e9be320b93ae804f8427b91dc3432afc';

Future<void> main(List<String> args) async {
  final force = args.contains('--force');
  final scriptDir = p.dirname(Platform.script.toFilePath());
  final packageRoot = p.normalize(p.join(scriptDir, '..'));
  final nativeDir = p.join(packageRoot, 'native');
  final dylibDest = p.join(nativeDir, 'lib', 'libonnxruntime.dylib');
  final headerDest = p.join(nativeDir, 'include', 'onnxruntime_c_api.h');

  final appSupportDir = p.join(
    Platform.environment['HOME'] ?? '',
    'Library',
    'Application Support',
    'isochron',
    'lib',
  );
  final appSupportDylib = p.join(appSupportDir, 'libonnxruntime.dylib');

  if (!force && File(dylibDest).existsSync() && File(headerDest).existsSync()) {
    stdout.writeln('[fetch_onnxruntime] ONNX Runtime $onnxVersion dylib & headers already present at $nativeDir');
    if (!File(appSupportDylib).existsSync()) {
      Directory(appSupportDir).createSync(recursive: true);
      File(dylibDest).copySync(appSupportDylib);
      stdout.writeln('[fetch_onnxruntime] Synced dylib to $appSupportDylib');
    }
    return;
  }

  stdout.writeln('[fetch_onnxruntime] Downloading ONNX Runtime $onnxVersion ($onnxArch)...');
  stdout.writeln('URL: $onnxUrl');

  final tempDir = Directory.systemTemp.createTempSync('ort_download_');
  final tarFile = File(p.join(tempDir.path, 'onnxruntime.tgz'));

  try {
    final client = http.Client();
    final request = http.Request('GET', onnxUrl);
    final response = await client.send(request);

    if (response.statusCode != 200) {
      throw Exception('Failed to download: HTTP ${response.statusCode}');
    }

    final totalBytes = response.contentLength ?? 0;
    var receivedBytes = 0;
    final sink = tarFile.openWrite();

    await for (final chunk in response.stream) {
      sink.add(chunk);
      receivedBytes += chunk.length;
      if (totalBytes > 0) {
        final pct = (receivedBytes / totalBytes * 100).toStringAsFixed(1);
        stdout.write('\rDownloading: $pct% ($receivedBytes / $totalBytes bytes)');
      }
    }
    await sink.flush();
    await sink.close();
    stdout.writeln('\nDownload complete.');

    stdout.writeln('Verifying SHA-256...');
    final bytes = await tarFile.readAsBytes();
    final digest = sha256.convert(bytes).toString();
    if (digest.toLowerCase() != expectedSha256.toLowerCase()) {
      throw Exception(
        'SHA-256 mismatch!\nExpected: $expectedSha256\nActual:   $digest',
      );
    }
    stdout.writeln('SHA-256 verified successfully.');

    // Extract headers and dylib
    final extractDir = p.join(tempDir.path, 'extracted');
    Directory(extractDir).createSync(recursive: true);

    final tarResult = await Process.run('/usr/bin/tar', [
      '-xzf',
      tarFile.path,
      '-C',
      extractDir,
    ]);
    if (tarResult.exitCode != 0) {
      throw Exception('Failed to extract tar archive: ${tarResult.stderr}');
    }

    final rootExtracted = p.join(extractDir, 'onnxruntime-$onnxArch-$onnxVersion');
    final srcInclude = p.join(rootExtracted, 'include');
    final srcLib = p.join(rootExtracted, 'lib');

    // Copy include headers
    final targetInclude = p.join(nativeDir, 'include');
    Directory(targetInclude).createSync(recursive: true);
    for (final entity in Directory(srcInclude).listSync()) {
      if (entity is File) {
        entity.copySync(p.join(targetInclude, p.basename(entity.path)));
      }
    }

    // Copy dylib
    final targetLib = p.join(nativeDir, 'lib');
    Directory(targetLib).createSync(recursive: true);
    final extractedDylib = File(p.join(srcLib, 'libonnxruntime.$onnxVersion.dylib'));
    if (extractedDylib.existsSync()) {
      extractedDylib.copySync(dylibDest);
    } else {
      final fallbackDylib = File(p.join(srcLib, 'libonnxruntime.dylib'));
      fallbackDylib.copySync(dylibDest);
    }

    // Copy to Application Support
    Directory(appSupportDir).createSync(recursive: true);
    File(dylibDest).copySync(appSupportDylib);

    stdout.writeln('Successfully installed ONNX Runtime:');
    stdout.writeln('  Headers: $targetInclude');
    stdout.writeln('  Dylib:   $dylibDest');
    stdout.writeln('  Cached:  $appSupportDylib');
  } finally {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  }
}
