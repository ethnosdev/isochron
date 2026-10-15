import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:isochron_cli/src/mms/model_manager.dart';
import 'package:test/test.dart';

void main() {
  group('ModelManager', () {
    late Directory tempDir;
    late ModelManager manager;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('mm_test_');
      manager = ModelManager(modelsDir: tempDir);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('initial status is notDownloaded', () async {
      final status = await manager.checkStatus(ModelVariant.int8);
      expect(status, equals(ModelStatus.notDownloaded));
    });

    test('corrupt status when file size does not match', () async {
      final file = manager.getFile(ModelVariant.int8);
      await file.writeAsString('small test content');

      final status = await manager.checkStatus(ModelVariant.int8);
      expect(status, equals(ModelStatus.corrupt));
    });

    test('ready status when file size matches', () async {
      final file = manager.getFile(ModelVariant.int8);
      // Create sparse or padded file of exact size for status check test
      final raf = await file.open(mode: FileMode.write);
      await raf.truncate(ModelVariant.int8.sizeBytes);
      await raf.close();

      final status = await manager.checkStatus(ModelVariant.int8);
      expect(status, equals(ModelStatus.ready));
    });

    test('delete removes both complete and partial files', () async {
      final file = manager.getFile(ModelVariant.int8);
      final partFile = manager.getPartFile(ModelVariant.int8);
      await file.writeAsString('done');
      await partFile.writeAsString('part');

      expect(await file.exists(), isTrue);
      expect(await partFile.exists(), isTrue);

      await manager.delete(ModelVariant.int8);

      expect(await file.exists(), isFalse);
      expect(await partFile.exists(), isFalse);
    });

    test('download fails on size mismatch with server', () async {
      final testData = utf8.encode('test model binary payload');
      final mockClient = MockClient((request) async {
        return http.Response.bytes(testData, 200, headers: {
          'content-length': testData.length.toString(),
        });
      });

      expect(
        () => manager.download(ModelVariant.int8, customClient: mockClient),
        throwsA(isA<Exception>()),
      );
    });
  });
}
