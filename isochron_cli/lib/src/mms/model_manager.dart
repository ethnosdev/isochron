import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

const String kPinnedHfCommit = '2100fb247d8e43962eef24491597fbeb8b469531';
const String kHfBaseUrl =
    'https://huggingface.co/onnx-community/mms-300m-1130-forced-aligner-ONNX/resolve/$kPinnedHfCommit/onnx';

enum ModelVariant {
  int8(
    filename: 'model_int8.onnx',
    sizeBytes: 317341664,
    sha256: '2eb5c3d2f6db2ef476aa7a7e1e5800145973e9064eb5292b1b9b8ada1207712a',
  ),
  fp16(
    filename: 'model_fp16.onnx',
    sizeBytes: 631591191,
    sha256: 'e98082b382375f3528ec7514e175b5cd0eb77fcc4d4531a7142b9e45a1ce6deb',
  ),
  fp32(
    filename: 'model.onnx',
    sizeBytes: 1262529881,
    sha256: '429e5d05c62acc8a9264db874a1b131e359fc626e40c253ac7b1fe52b11149b4',
  );

  final String filename;
  final int sizeBytes;
  final String sha256;

  const ModelVariant({
    required this.filename,
    required this.sizeBytes,
    required this.sha256,
  });

  Uri get downloadUrl => Uri.parse('$kHfBaseUrl/$filename');
}

enum ModelStatus {
  notDownloaded,
  downloading,
  verifying,
  ready,
  corrupt,
}

class ModelManager {
  final Directory modelsDir;

  ModelManager({Directory? modelsDir})
      : modelsDir = modelsDir ?? _defaultModelsDir();

  static Directory _defaultModelsDir() {
    final home = Platform.environment['HOME'] ?? '';
    return Directory(
      p.join(home, 'Library', 'Application Support', 'isochron', 'models'),
    );
  }

  File getFile(ModelVariant variant) =>
      File(p.join(modelsDir.path, variant.filename));

  File getPartFile(ModelVariant variant) =>
      File(p.join(modelsDir.path, '${variant.filename}.part'));

  /// Checks the current status of the given model variant.
  /// If [verifySha] is true and the file exists with the expected size,
  /// its SHA-256 hash is verified before returning [ModelStatus.ready].
  Future<ModelStatus> checkStatus(
    ModelVariant variant, {
    bool verifySha = false,
  }) async {
    final file = getFile(variant);
    if (!await file.exists()) {
      return ModelStatus.notDownloaded;
    }

    final length = await file.length();
    if (length != variant.sizeBytes) {
      return ModelStatus.corrupt;
    }

    if (verifySha) {
      final isValid = await verifyHash(variant);
      return isValid ? ModelStatus.ready : ModelStatus.corrupt;
    }

    return ModelStatus.ready;
  }

  /// Verifies the SHA-256 checksum of an existing model file.
  Future<bool> verifyHash(ModelVariant variant) async {
    final file = getFile(variant);
    if (!await file.exists()) return false;

    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase() == variant.sha256.toLowerCase();
  }

  /// Downloads the specified model variant, supporting resumable downloads via HTTP Range.
  Future<File> download(
    ModelVariant variant, {
    void Function(double progress, int receivedBytes, int totalBytes)? onProgress,
    bool Function()? isCancelled,
    http.Client? customClient,
  }) async {
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }

    final targetFile = getFile(variant);
    if (await targetFile.exists()) {
      final length = await targetFile.length();
      if (length == variant.sizeBytes) {
        onProgress?.call(1.0, variant.sizeBytes, variant.sizeBytes);
        return targetFile;
      }
    }

    final partFile = getPartFile(variant);
    var existingBytes = 0;
    if (await partFile.exists()) {
      existingBytes = await partFile.length();
      if (existingBytes > variant.sizeBytes) {
        // Corrupted part file that exceeds size
        await partFile.delete();
        existingBytes = 0;
      }
    }

    final client = customClient ?? http.Client();
    try {
      final request = http.Request('GET', variant.downloadUrl);
      if (existingBytes > 0) {
        request.headers['Range'] = 'bytes=$existingBytes-';
      }

      final response = await client.send(request);
      final isPartial = response.statusCode == 206;
      final isOk = response.statusCode == 200;

      if (!isOk && !isPartial) {
        throw HttpException(
          'Download failed: HTTP ${response.statusCode} (${response.reasonPhrase})',
          uri: variant.downloadUrl,
        );
      }

      final fileMode = (isPartial && existingBytes > 0)
          ? FileMode.append
          : FileMode.write;
      var currentBytes = (isPartial && existingBytes > 0) ? existingBytes : 0;
      final sink = partFile.openWrite(mode: fileMode);

      final totalBytes = variant.sizeBytes;

      try {
        await for (final chunk in response.stream) {
          if (isCancelled?.call() == true) {
            await sink.flush();
            await sink.close();
            throw CancellationException('Model download cancelled by user');
          }
          sink.add(chunk);
          currentBytes += chunk.length;
          final pct = totalBytes > 0 ? (currentBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
          onProgress?.call(pct, currentBytes, totalBytes);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      // Verify file size and checksum
      final partLength = await partFile.length();
      if (partLength != variant.sizeBytes) {
        throw HttpException(
          'Downloaded size ($partLength bytes) does not match expected (${variant.sizeBytes} bytes)',
          uri: variant.downloadUrl,
        );
      }

      final digest = await sha256.bind(partFile.openRead()).first;
      if (digest.toString().toLowerCase() != variant.sha256.toLowerCase()) {
        await partFile.delete();
        throw HttpException(
          'Downloaded model failed SHA-256 verification!\nExpected: ${variant.sha256}\nGot: $digest',
          uri: variant.downloadUrl,
        );
      }

      // Atomically move part to target file
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await partFile.rename(targetFile.path);
      onProgress?.call(1.0, variant.sizeBytes, variant.sizeBytes);
      return targetFile;
    } finally {
      if (customClient == null) {
        client.close();
      }
    }
  }

  /// Deletes the model file and any in-progress download part file.
  Future<void> delete(ModelVariant variant) async {
    final file = getFile(variant);
    if (await file.exists()) {
      await file.delete();
    }
    final partFile = getPartFile(variant);
    if (await partFile.exists()) {
      await partFile.delete();
    }
  }
}

class CancellationException implements Exception {
  final String message;
  CancellationException([this.message = 'Operation cancelled']);
  @override
  String toString() => message;
}
