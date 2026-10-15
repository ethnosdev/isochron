import 'dart:io';
import 'package:isochron_cli/src/mms/model_manager.dart';

Future<void> main(List<String> args) async {
  final manager = ModelManager();
  final variant = ModelVariant.int8;

  stdout.writeln('Checking status of ${variant.filename}...');
  final status = await manager.checkStatus(variant, verifySha: true);
  if (status == ModelStatus.ready) {
    stdout.writeln('Model is already downloaded and verified: ${manager.getFile(variant).path}');
    return;
  }

  stdout.writeln('Downloading ${variant.filename} (${(variant.sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB)...');
  stdout.writeln('Destination: ${manager.getFile(variant).path}');

  final file = await manager.download(
    variant,
    onProgress: (progress, received, total) {
      final pct = (progress * 100).toStringAsFixed(1);
      final mbReceived = (received / 1024 / 1024).toStringAsFixed(1);
      final mbTotal = (total / 1024 / 1024).toStringAsFixed(1);
      stdout.write('\rDownloading: $pct% ($mbReceived / $mbTotal MB)');
    },
  );

  stdout.writeln('\nDownload & SHA-256 verification complete: ${file.path}');
}
