import 'dart:io';
import 'package:test/test.dart';
import 'package:isochron_cli/src/core/fragment.dart';
import 'package:isochron_cli/src/synthesis/anchor_generator.dart'; // To be created

void main() {
  group('AnchorGenerator', () {
    // NOTE: These tests require espeak-ng to be installed.
    // If you are in an environment without it, these will fail.

    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('isochron_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('should generate audio and update timestamps', () async {
      // 1. Prepare Data
      final fragments = [
        Fragment(index: 0, text: 'Hello'),
        Fragment(index: 1, text: 'World'),
      ];

      // 2. Run Generator
      final generator = AnchorGenerator();
      final File outputFile = await generator.generate(fragments, tempDir);

      // 3. Verify File Exists
      expect(outputFile.existsSync(), isTrue);
      expect(
          outputFile.lengthSync(), greaterThan(100)); // Should have some data

      // 4. Verify Timestamps
      // Fragment 0 should start at 0
      expect(fragments[0].anchorStart, 0.0);
      expect(fragments[0].anchorEnd, greaterThan(0.0));

      // Fragment 1 should start where Fragment 0 ended
      expect(fragments[1].anchorStart, fragments[0].anchorEnd);
      expect(fragments[1].anchorEnd, greaterThan(fragments[1].anchorStart));
    });
  });
}
