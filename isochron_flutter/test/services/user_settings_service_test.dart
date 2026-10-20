import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late UserSettingsService settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = UserSettingsService();
    await settings.init();
    tempDir = await Directory.systemTemp.createTemp('user_settings_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('UserSettingsService Recent Projects', () {
    test('recentProjects extracts project name from project.json and updates when renamed',
        () async {
      // 1. Create a project directory named "Untitled Project"
      final projectDir = Directory(p.join(tempDir.path, 'Untitled Project'));
      await projectDir.create();

      final projectFile = File(p.join(projectDir.path, 'project.json'));
      await projectFile.writeAsString(jsonEncode({
        'id': 'test-id',
        'name': 'Original Name',
        'collections': [],
      }));

      // 2. Add to recent projects
      await settings.addRecentProject(projectFile.path);

      // 3. Verify recentProjects reflects the name in project.json, not the directory name
      expect(settings.recentProjects.length, equals(1));
      expect(settings.recentProjects.first.name, equals('Original Name'));
      expect(settings.recentProjects.first.directory, equals(projectDir.path));

      // 4. Rename the project in project.json (as happens when renaming in app)
      await projectFile.writeAsString(jsonEncode({
        'id': 'test-id',
        'name': 'Renamed Bible Project',
        'collections': [],
      }));

      // 5. Verify recentProjects immediately reflects the updated project name
      expect(settings.recentProjects.first.name, equals('Renamed Bible Project'));
    });

    test('recentProjects falls back to directory name when project.json is missing name',
        () async {
      final projectDir = Directory(p.join(tempDir.path, 'My Special Folder'));
      await projectDir.create();

      final projectFile = File(p.join(projectDir.path, 'project.json'));
      await projectFile.writeAsString(jsonEncode({
        'id': 'test-id',
        'collections': [],
      }));

      await settings.addRecentProject(projectFile.path);

      expect(settings.recentProjects.length, equals(1));
      expect(settings.recentProjects.first.name, equals('My Special Folder'));
    });
  });
}
