import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:isochron_flutter/ui/workspace/workspace_manager.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Media Consolidation Tests', () {
    late Directory tempProjectDir;
    late Directory tempExternalDir;
    late WorkspaceManager manager;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await UserSettingsService().init();
      tempProjectDir = await Directory.systemTemp.createTemp('isochron_test_proj_');
      tempExternalDir = await Directory.systemTemp.createTemp('isochron_test_ext_');
      manager = WorkspaceManager();
    });

    tearDown(() async {
      if (tempProjectDir.existsSync()) {
        tempProjectDir.deleteSync(recursive: true);
      }
      if (tempExternalDir.existsSync()) {
        tempExternalDir.deleteSync(recursive: true);
      }
    });

    test('hasExternalMedia correctly detects external paths and consolidateExternalMedia copies files', () async {
      await manager.createProject(
        tempProjectDir.path,
        'TestProject',
        firstCollectionName: 'Main',
        copyMediaIntoProject: false,
      );

      final col = manager.project!.collections.first;

      // Create external files
      final extAudio = File(p.join(tempExternalDir.path, 'track_001.mp3'));
      await extAudio.writeAsString('dummy audio data');

      final extText = File(p.join(tempExternalDir.path, 'track_001.txt'));
      await extText.writeAsString('dummy transcript data');

      final track = Track(
        id: 'track-1',
        name: 'Track 1',
        audioPath: extAudio.path,
        textPath: extText.path,
        outputFilename: 'track_1.json',
      );
      col.tracks.add(track);
      await col.saveTracks(tempProjectDir.path);

      // Verify hasExternalMedia is true
      expect(manager.hasExternalMedia(), isTrue);

      // Run consolidateExternalMedia
      final count = await manager.consolidateExternalMedia();
      expect(count, equals(2));

      // Verify track paths are now relative basenames
      expect(track.audioPath, equals('track_001.mp3'));
      expect(track.textPath, equals('track_001.txt'));

      // Verify files exist in project collections folder
      final internalAudio = File(
        p.join(tempProjectDir.path, 'collections', col.folderName, 'audio', 'track_001.mp3'),
      );
      final internalText = File(
        p.join(tempProjectDir.path, 'collections', col.folderName, 'text', 'track_001.txt'),
      );

      expect(internalAudio.existsSync(), isTrue);
      expect(internalText.existsSync(), isTrue);
      expect(await internalAudio.readAsString(), equals('dummy audio data'));
      expect(await internalText.readAsString(), equals('dummy transcript data'));

      // Verify hasExternalMedia is now false
      expect(manager.hasExternalMedia(), isFalse);
    });
  });
}
