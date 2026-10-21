import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:isochron_flutter/ui/workspace/workspace_manager.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await UserSettingsService().init();
    tempDir = Directory.systemTemp.createTempSync('directory_watcher_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Project.reloadCollection', () {
    test('reloads updated track list and statuses from disk', () async {
      final project = Project(
        id: 'p1',
        name: 'Sync Test Project',
        directoryPath: tempDir.path,
      );

      final col = Collection(id: 'c1', name: 'Genesis');
      col.tracks.add(
        Track(
          id: 't1',
          collectionId: 'c1',
          name: 'Chapter 01',
          outputFilename: 'GEN_01_timing.json',
          status: AlignmentStatus.pending,
        ),
      );
      project.collections.add(col);

      // Save initial state to disk
      await project.save();

      // Simulate a remote collaborator saving updated collection.json
      final colFile = File(
        p.join(tempDir.path, 'collections', col.folderName, 'collection.json'),
      );
      expect(colFile.existsSync(), isTrue);

      final updatedJson = {
        'id': 'c1',
        'name': 'Genesis',
        'tracks': [
          {
            'id': 't1',
            'name': 'Chapter 01',
            'outputFilename': 'GEN_01_timing.json',
            'status': 'reviewed',
          },
          {
            'id': 't2',
            'name': 'Chapter 02',
            'outputFilename': 'GEN_02_timing.json',
            'status': 'done',
          },
        ],
      };
      await colFile.writeAsString(jsonEncode(updatedJson));

      // In-memory collection still has 1 pending track
      expect(col.tracks.length, 1);
      expect(col.tracks.first.status, AlignmentStatus.pending);

      // Reload
      await project.reloadCollection(col);

      // Verify updated
      expect(col.tracks.length, 2);
      expect(col.tracks[0].id, 't1');
      expect(col.tracks[0].status, AlignmentStatus.reviewed);
      expect(col.tracks[1].id, 't2');
      expect(col.tracks[1].status, AlignmentStatus.aligned);
    });

    test('preserves track object reference and processing status when reloading collection', () async {
      final project = Project(
        id: 'p2',
        name: 'Preserve Status Project',
        directoryPath: tempDir.path,
      );

      final col = Collection(id: 'c2', name: 'Exodus');
      final originalTrack1 = Track(
        id: 't_active',
        collectionId: 'c2',
        name: 'Chapter 01',
        outputFilename: 'EXO_01_timing.json',
        status: AlignmentStatus.processing,
      );
      col.tracks.add(originalTrack1);
      project.collections.add(col);

      await project.save();

      final colFile = File(
        p.join(tempDir.path, 'collections', col.folderName, 'collection.json'),
      );

      // Simulate external write saving track as pending
      final updatedJson = {
        'id': 'c2',
        'name': 'Exodus',
        'tracks': [
          {
            'id': 't_active',
            'name': 'Chapter 01 Renamed',
            'outputFilename': 'EXO_01_timing.json',
            'status': 'pending',
          },
        ],
      };
      await colFile.writeAsString(jsonEncode(updatedJson));

      await project.reloadCollection(col);

      // Must preserve the identical in-memory instance
      expect(identical(col.tracks.first, originalTrack1), isTrue);
      // Must preserve processing status
      expect(col.tracks.first.status, AlignmentStatus.processing);
      // Must update other fields
      expect(col.tracks.first.name, 'Chapter 01 Renamed');
    });

    test('auto-heals pending track to done if alignment file exists', () async {
      final project = Project(
        id: 'p3',
        name: 'Auto-Heal Project',
        directoryPath: tempDir.path,
      );

      final col = Collection(id: 'c3', name: 'Leviticus');
      final track = Track(
        id: 't_heal',
        collectionId: 'c3',
        name: 'Chapter 01',
        outputFilename: 'LEV_01_timing.json',
        status: AlignmentStatus.pending,
      );
      col.tracks.add(track);
      project.collections.add(col);

      await project.save();

      // Create alignment file on disk
      final alignFile = File(
        p.join(tempDir.path, 'collections', col.folderName, 'alignments', 'LEV_01_timing.json'),
      );
      await alignFile.parent.create(recursive: true);
      await alignFile.writeAsString('[]');

      await project.reloadCollection(col);

      expect(track.status, AlignmentStatus.aligned);
    });
  });

  group('WorkspaceManager Watcher Lifecycle', () {
    test('starts watcher on createProject and stops on closeProject', () async {
      final wm = WorkspaceManager();

      expect(wm.isWatcherActive, isFalse);

      final projectDir = p.join(tempDir.path, 'TestProject');
      await wm.createProject(projectDir, 'TestProject');

      expect(wm.isWatcherActive, isTrue);

      wm.closeProject();

      expect(wm.isWatcherActive, isFalse);
      wm.dispose();
    });

    test('stops watcher on dispose', () async {
      final wm = WorkspaceManager();
      final projectDir = p.join(tempDir.path, 'TestProject');
      await wm.createProject(projectDir, 'TestProject');

      expect(wm.isWatcherActive, isTrue);

      wm.dispose();
      expect(wm.isWatcherActive, isFalse);
    });
  });

  group('WorkspaceManager Remote Sync Handlers', () {
    test('handles collection.json remote update', () async {
      final wm = WorkspaceManager();
      final projectDir = p.join(tempDir.path, 'TestProject');
      await wm.createProject(projectDir, 'TestProject');

      final col = wm.project!.collections.first;
      final colFile = File(
        p.join(projectDir, 'collections', col.folderName, 'collection.json'),
      );

      // Add a track on disk remotely
      final updatedJson = {
        'id': col.id,
        'name': col.name,
        'tracks': [
          {
            'id': 'remote_t1',
            'name': 'Remote Track 1',
            'outputFilename': 'remote_01_timing.json',
            'status': 'done',
          },
        ],
      };
      await colFile.writeAsString(jsonEncode(updatedJson));

      bool notified = false;
      wm.addListener(() => notified = true);

      await wm.handleRemoteSyncForTest(colFile.path);

      expect(notified, isTrue);
      expect(col.tracks.length, 1);
      expect(col.tracks.first.id, 'remote_t1');
      expect(col.tracks.first.status, AlignmentStatus.aligned);

      wm.dispose();
    });

    test('handles remote alignment completion updating pending track to done', () async {
      final wm = WorkspaceManager();
      final projectDir = p.join(tempDir.path, 'TestProject');
      await wm.createProject(projectDir, 'TestProject');

      final col = wm.project!.collections.first;
      final track = Track(
        id: 't_pending',
        collectionId: col.id,
        name: 'Pending Track',
        outputFilename: 'pending_timing.json',
        status: AlignmentStatus.pending,
      );
      col.tracks.add(track);

      final alignmentFile = File(
        p.join(
          projectDir,
          'collections',
          col.folderName,
          'alignments',
          'pending_timing.json',
        ),
      );
      await alignmentFile.parent.create(recursive: true);
      await alignmentFile.writeAsString('[]');

      bool notified = false;
      wm.addListener(() => notified = true);

      await wm.handleRemoteSyncForTest(alignmentFile.path);

      expect(notified, isTrue);
      expect(track.status, AlignmentStatus.aligned);

      wm.dispose();
    });

    test('handles project.json remote update adding new collection', () async {
      final wm = WorkspaceManager();
      final projectDir = p.join(tempDir.path, 'TestProject');
      await wm.createProject(projectDir, 'TestProject');

      expect(wm.project!.collections.length, 1);

      // Simulate collaborator creating and saving a second collection in project.json
      final projectJsonFile = File(p.join(projectDir, 'project.json'));
      final projectData = wm.project!.toJson();
      (projectData['collections'] as List).add({
        'id': 'c2_new',
        'name': 'Second Collection',
      });
      await projectJsonFile.writeAsString(jsonEncode(projectData));

      bool notified = false;
      wm.addListener(() => notified = true);

      await wm.handleRemoteSyncForTest(projectJsonFile.path);

      expect(notified, isTrue);
      expect(wm.project!.collections.length, 2);
      expect(wm.project!.collections.any((c) => c.id == 'c2_new'), isTrue);

      wm.dispose();
    });
  });

  group('Directory Watcher Real Filesystem Event', () {
    test('debounces and notifies when file is modified in collections', () async {
      final wm = WorkspaceManager();
      wm.watcherDebounceDuration = const Duration(milliseconds: 50);

      final projectDir = p.join(tempDir.path, 'TestProject');
      await wm.createProject(projectDir, 'TestProject');

      final col = wm.project!.collections.first;
      final claimFile = File(
        p.join(
          projectDir,
          'collections',
          col.folderName,
          'alignments',
          'chapter_01.claim.json',
        ),
      );
      await claimFile.parent.create(recursive: true);

      int notifyCount = 0;
      wm.addListener(() => notifyCount++);

      // Write claim file to filesystem to trigger OS file watcher
      await claimFile.writeAsString(
        jsonEncode({'user': 'Teammate Tim', 'claimedAt': DateTime.now().toIso8601String()}),
      );

      // Wait for debounce duration + buffer
      await Future.delayed(const Duration(milliseconds: 250));

      expect(notifyCount, greaterThanOrEqualTo(1));

      wm.dispose();
    });
  });
}
