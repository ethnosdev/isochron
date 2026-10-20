import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isochron_flutter/services/alignment_service.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:isochron_flutter/ui/workspace/workspace_manager.dart';
import 'package:isochron_flutter/utils/file_sync_tracker.dart';
import 'package:isochron_flutter/utils/media_pairing_engine.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await UserSettingsService().init();
    FileSyncTracker.clear();
    tempDir = Directory.systemTemp.createTempSync('manage_pairings_test_');
  });

  tearDown(() {
    FileSyncTracker.clear();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test(
      'updateCollectionTracks preserves untouched tracks and resets modified tracks',
      () async {
    final colDir = Directory(p.join(tempDir.path, 'collections', 'NT'));
    final alignDir = Directory(p.join(colDir.path, 'alignments'));
    alignDir.createSync(recursive: true);

    final timingFile1 = File(p.join(alignDir.path, 'track1_timing.json'));
    timingFile1.writeAsStringSync('{"fragments": []}');
    final timingFile2 = File(p.join(alignDir.path, 'track2_timing.json'));
    timingFile2.writeAsStringSync('{"fragments": []}');

    final track1 = Track(
      id: 't1',
      collectionId: 'col1',
      name: 'track1',
      audioPath: '/media/track1.mp3',
      textPath: '/media/track1.txt',
      outputFilename: 'track1_timing.json',
      status: AlignmentStatus.done,
    );
    final track2 = Track(
      id: 't2',
      collectionId: 'col1',
      name: 'track2',
      audioPath: '/media/track2.mp3',
      textPath: '/media/old_track2.txt',
      outputFilename: 'track2_timing.json',
      status: AlignmentStatus.done,
    );

    final col = Collection(
      id: 'col1',
      name: 'NT',
      tracks: [track1, track2],
    );

    final project = Project(
      id: 'proj1',
      name: 'Test Project',
      directoryPath: tempDir.path,
      collections: [col],
    );

    final wm = WorkspaceManager(
      customAlignmentService: AlignmentService.forTesting(),
    );
    wm.project = project;

    final newRows = [
      // Track 1 is untouched
      PairedRow(
        name: 'track1',
        audioPath: '/media/track1.mp3',
        textPath: '/media/track1.txt',
      ),
      // Track 2 has its text modified
      PairedRow(
        name: 'track2',
        audioPath: '/media/track2.mp3',
        textPath: '/media/new_track2.txt',
      ),
      // Track 3 is newly added
      PairedRow(
        name: 'track3',
        audioPath: '/media/track3.mp3',
        textPath: '/media/track3.txt',
      ),
    ];

    await wm.updateCollectionTracks(
      null,
      col,
      newRows,
      skipConfirmation: true,
    );

    expect(col.tracks.length, 3);

    // Track 1: untouched
    expect(col.tracks[0].id, 't1');
    expect(col.tracks[0].status, AlignmentStatus.done);
    expect(timingFile1.existsSync(), isTrue);

    // Track 2: reset to pending, timing JSON deleted
    expect(col.tracks[1].id, 't2');
    expect(col.tracks[1].status, AlignmentStatus.pending);
    expect(col.tracks[1].textPath, '/media/new_track2.txt');
    expect(timingFile2.existsSync(), isFalse);

    // Track 3: newly added
    expect(col.tracks[2].name, 'track3');
    expect(col.tracks[2].status, AlignmentStatus.pending);
  });

  test('updateCollectionTracks deletes removed tracks and their timing files',
      () async {
    final colDir = Directory(p.join(tempDir.path, 'collections', 'NT'));
    final alignDir = Directory(p.join(colDir.path, 'alignments'));
    alignDir.createSync(recursive: true);

    final timingFile1 = File(p.join(alignDir.path, 'track1_timing.json'));
    timingFile1.writeAsStringSync('{"fragments": []}');
    final timingFile2 = File(p.join(alignDir.path, 'track2_timing.json'));
    timingFile2.writeAsStringSync('{"fragments": []}');

    final track1 = Track(
      id: 't1',
      collectionId: 'col1',
      name: 'track1',
      audioPath: '/media/track1.mp3',
      textPath: '/media/track1.txt',
      outputFilename: 'track1_timing.json',
      status: AlignmentStatus.done,
    );
    final track2 = Track(
      id: 't2',
      collectionId: 'col1',
      name: 'track2',
      audioPath: '/media/track2.mp3',
      textPath: '/media/track2.txt',
      outputFilename: 'track2_timing.json',
      status: AlignmentStatus.done,
    );

    final col = Collection(
      id: 'col1',
      name: 'NT',
      tracks: [track1, track2],
    );

    final project = Project(
      id: 'proj1',
      name: 'Test Project',
      directoryPath: tempDir.path,
      collections: [col],
    );

    final wm = WorkspaceManager(
      customAlignmentService: AlignmentService.forTesting(),
    );
    wm.project = project;

    // Only keep Track 1, remove Track 2
    final newRows = [
      PairedRow(
        name: 'track1',
        audioPath: '/media/track1.mp3',
        textPath: '/media/track1.txt',
      ),
    ];

    await wm.updateCollectionTracks(
      null,
      col,
      newRows,
      skipConfirmation: true,
    );

    expect(col.tracks.length, 1);
    expect(col.tracks[0].id, 't1');
    expect(timingFile1.existsSync(), isTrue);
    expect(timingFile2.existsSync(), isFalse);
  });

  test('clearAllTracksInCollection wipes all tracks and files', () async {
    final colDir = Directory(p.join(tempDir.path, 'collections', 'NT'));
    final alignDir = Directory(p.join(colDir.path, 'alignments'));
    alignDir.createSync(recursive: true);

    final timingFile1 = File(p.join(alignDir.path, 'track1_timing.json'));
    timingFile1.writeAsStringSync('{"fragments": []}');

    final track1 = Track(
      id: 't1',
      collectionId: 'col1',
      name: 'track1',
      audioPath: '/media/track1.mp3',
      textPath: '/media/track1.txt',
      outputFilename: 'track1_timing.json',
      status: AlignmentStatus.done,
    );

    final col = Collection(
      id: 'col1',
      name: 'NT',
      tracks: [track1],
    );

    final project = Project(
      id: 'proj1',
      name: 'Test Project',
      directoryPath: tempDir.path,
      collections: [col],
    );

    final wm = WorkspaceManager(
      customAlignmentService: AlignmentService.forTesting(),
    );
    wm.project = project;

    await wm.clearAllTracksInCollection(
      null,
      col,
      skipConfirmation: true,
    );

    expect(col.tracks.isEmpty, isTrue);
    expect(timingFile1.existsSync(), isFalse);
  });
}
