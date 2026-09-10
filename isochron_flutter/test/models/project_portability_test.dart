import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('project_portability_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Project Serialization Portability', () {
    test('toJson does not serialize directoryPath', () {
      final project = Project(
        id: 'test-uuid-1234',
        name: 'Portable Bible Project',
        directoryPath: '/Users/someone/Projects/PortableBible',
      );

      final jsonMap = project.toJson();

      expect(jsonMap.containsKey('directoryPath'), isFalse);
      expect(jsonMap['id'], 'test-uuid-1234');
      expect(jsonMap['name'], 'Portable Bible Project');
    });

    test('fromJson handles legacy JSON containing directoryPath', () {
      final legacyJson = {
        'id': 'legacy-id',
        'name': 'Legacy Project',
        'directoryPath': '/old/stale/machine/path',
        'collections': [
          {'id': 'c1', 'name': 'Genesis'},
        ],
      };

      final project = Project.fromJson(legacyJson);

      expect(project.id, 'legacy-id');
      expect(project.name, 'Legacy Project');
      expect(project.directoryPath, '/old/stale/machine/path');
    });

    test('fromJson handles modern JSON without directoryPath', () {
      final modernJson = {
        'id': 'modern-id',
        'name': 'Modern Project',
        'collections': [
          {'id': 'c1', 'name': 'Genesis'},
        ],
      };

      final project = Project.fromJson(modernJson);

      expect(project.id, 'modern-id');
      expect(project.name, 'Modern Project');
      expect(project.directoryPath, '');
    });
  });

  group('Targeted Saves Isolation', () {
    test('saveSettingsOnly updates project.json without touching collection files', () async {
      final projectDir = tempDir.path;
      final collectionsDir = Directory(p.join(projectDir, 'collections'));
      await collectionsDir.create(recursive: true);

      final colGenesis = Collection(id: 'col-gen', name: 'Genesis');
      final colExodus = Collection(id: 'col-exo', name: 'Exodus');

      final project = Project(
        id: 'proj-1',
        name: 'Test Project',
        directoryPath: projectDir,
        collections: [colGenesis, colExodus],
      );

      // Perform initial full save
      await project.save();

      final projectJsonFile = File(p.join(projectDir, 'project.json'));
      final genesisJsonFile = File(
        p.join(projectDir, 'collections', 'Genesis', 'collection.json'),
      );
      final exodusJsonFile = File(
        p.join(projectDir, 'collections', 'Exodus', 'collection.json'),
      );

      expect(projectJsonFile.existsSync(), isTrue);
      expect(genesisJsonFile.existsSync(), isTrue);
      expect(exodusJsonFile.existsSync(), isTrue);

      final genModTimeBefore = genesisJsonFile.lastModifiedSync();
      final exoModTimeBefore = exodusJsonFile.lastModifiedSync();

      // Wait a short duration to ensure file timestamp differences are detectable
      await Future.delayed(const Duration(milliseconds: 50));

      // Modify project settings and save ONLY settings
      project.name = 'Updated Project Name';
      project.snapMode = 'gap';
      await project.saveSettingsOnly();

      // Verify project.json was updated
      final updatedProjectJson = jsonDecode(await projectJsonFile.readAsString());
      expect(updatedProjectJson['name'], 'Updated Project Name');
      expect(updatedProjectJson['snapMode'], 'gap');
      expect(updatedProjectJson.containsKey('directoryPath'), isFalse);

      // Verify collection files were untouched
      expect(genesisJsonFile.lastModifiedSync(), genModTimeBefore);
      expect(exodusJsonFile.lastModifiedSync(), exoModTimeBefore);
    });

    test('saveCollectionOnly updates only the targeted collection and leaves others untouched', () async {
      final projectDir = tempDir.path;
      final collectionsDir = Directory(p.join(projectDir, 'collections'));
      await collectionsDir.create(recursive: true);

      final colGenesis = Collection(
        id: 'col-gen',
        name: 'Genesis',
        tracks: [
          Track(
            id: 't-gen-1',
            name: 'GEN_01',
            outputFilename: 'GEN_01_timing.json',
            status: AlignmentStatus.pending,
          ),
        ],
      );
      final colExodus = Collection(
        id: 'col-exo',
        name: 'Exodus',
        tracks: [
          Track(
            id: 't-exo-1',
            name: 'EXO_01',
            outputFilename: 'EXO_01_timing.json',
            status: AlignmentStatus.pending,
          ),
        ],
      );

      final project = Project(
        id: 'proj-1',
        name: 'Test Project',
        directoryPath: projectDir,
        collections: [colGenesis, colExodus],
      );

      // Initial save
      await project.save();

      final projectJsonFile = File(p.join(projectDir, 'project.json'));
      final genesisJsonFile = File(
        p.join(projectDir, 'collections', 'Genesis', 'collection.json'),
      );
      final exodusJsonFile = File(
        p.join(projectDir, 'collections', 'Exodus', 'collection.json'),
      );

      final projectModTimeBefore = projectJsonFile.lastModifiedSync();
      final exoModTimeBefore = exodusJsonFile.lastModifiedSync();

      await Future.delayed(const Duration(milliseconds: 50));

      // Alice reviews Genesis 1
      colGenesis.tracks.first.status = AlignmentStatus.reviewed;
      await project.saveCollectionOnly(colGenesis);

      // Verify Genesis collection file was updated with reviewed status
      final genesisContent = jsonDecode(await genesisJsonFile.readAsString());
      expect(genesisContent['tracks'][0]['status'], AlignmentStatus.reviewed.index);

      // Verify project.json and Exodus collection were NOT touched
      expect(projectJsonFile.lastModifiedSync(), projectModTimeBefore);
      expect(exodusJsonFile.lastModifiedSync(), exoModTimeBefore);
    });
  });
}
