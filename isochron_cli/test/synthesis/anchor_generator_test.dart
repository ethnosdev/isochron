import 'dart:io';
import 'package:isochron_cli/isochron_cli.dart';
import 'package:test/test.dart';

void main() {
  group('AnchorGenerator', () {
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

      // 2. Initialize macOS Drivers
      final audioDriver = MacAudioDriver();
      final ttsDriver = MacTtsDriver();

      // 3. Run Generator (Injecting the drivers)
      final generator = AnchorGenerator(
        audioDriver: audioDriver,
        ttsDriver: ttsDriver,
      );

      final File outputFile = await generator.generate(fragments, tempDir);

      // 4. Verify File Exists
      expect(outputFile.existsSync(), isTrue);
      expect(
          outputFile.lengthSync(), greaterThan(100)); // Should have some data

      // 5. Verify Timestamps
      // Fragment 0 should start at 0
      expect(fragments[0].anchorStart, 0.0);
      expect(fragments[0].anchorEnd, greaterThan(0.0));

      // Fragment 1 should start where Fragment 0 ended
      expect(fragments[1].anchorStart, fragments[0].anchorEnd);
      expect(fragments[1].anchorEnd, greaterThan(fragments[1].anchorStart));
    },
        skip: !Platform.isMacOS
            ? 'Requires macOS native tools (afconvert, say).'
            : false);
  });
}
