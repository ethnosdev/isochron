import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isochron_cli/isochron_cli.dart';
import 'package:isochron_flutter/services/alignment_service.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:isochron_flutter/ui/workspace/workspace_manager.dart';
import 'package:isochron_flutter/utils/file_sync_tracker.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class FakeAlignmentService extends AlignmentService {
  final List<String> alignedAudios = [];
  void Function(String trackName)? onTrackAlignStarted;

  FakeAlignmentService() : super.forTesting();

  @override
  Future<List<Fragment>> align({
    required String textPath,
    required String audioPath,
    String? languageCode,
    double leadInSeconds = 0.19,
    double starScore = -2.0,
    StarPlacement starPlacement = StarPlacement.segment,
    String? modelPath,
    ModelVariant modelVariant = ModelVariant.int8,
    bool snapToPauses = true,
    bool keepEdits = false,
    List<Fragment>? existingFragments,
    bool hasIds = false,
    bool generateIds = false,
    String? generatedIdPrefix,
    int recordingNumber = 1,
    required void Function(String status, double progress) onProgress,
  }) async {
    alignedAudios.add(audioPath);
    onProgress('Computing embeddings...', 0.5);
    onProgress('Done', 1.0);
    return [
      Fragment(index: 0, text: 'Verse 1')..setRealTiming(start: 0.0, end: 2.0),
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await UserSettingsService().init();
    FileSyncTracker.clear();
    tempDir = Directory.systemTemp.createTempSync('batch_alignment_test_');
  });

  tearDown(() {
    FileSyncTracker.clear();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('Batch alignment on remaining tracks (3 and 4) properly updates status and progress', () async {
    final fakeAligner = FakeAlignmentService();
    final wm = WorkspaceManager(customAlignmentService: fakeAligner);

    final projectDir = p.join(tempDir.path, 'BatchProject');
    await wm.createProject(projectDir, 'BatchProject');

    final col = wm.project!.collections.first;
    final audioDir = Directory(p.join(projectDir, 'collections', col.folderName, 'audio'));
    final textDir = Directory(p.join(projectDir, 'collections', col.folderName, 'text'));
    await audioDir.create(recursive: true);
    await textDir.create(recursive: true);

    // Create 4 dummy audio/text tracks
    for (int i = 1; i <= 4; i++) {
      final aFile = File(p.join(audioDir.path, 'track_0$i.wav'));
      final tFile = File(p.join(textDir.path, 'track_0$i.txt'));
      await aFile.writeAsString('RIFF dummy audio $i');
      await tFile.writeAsString('Verse $i line');

      final track = Track(
        id: 't$i',
        collectionId: col.id,
        name: 'Track $i',
        audioPath: 'track_0$i.wav',
        textPath: 'track_0$i.txt',
        outputFilename: 'track_0${i}_timing.json',
        status: (i <= 2) ? AlignmentStatus.done : AlignmentStatus.pending,
      );
      col.tracks.add(track);
    }
    await col.saveTracks(projectDir);

    expect(col.tracks[0].status, AlignmentStatus.done);
    expect(col.tracks[1].status, AlignmentStatus.done);
    expect(col.tracks[2].status, AlignmentStatus.pending);
    expect(col.tracks[3].status, AlignmentStatus.pending);

    // Track status notifications history for Track 4
    final track4Statuses = <AlignmentStatus>[];
    wm.addListener(() {
      final t4 = col.tracks.firstWhere((t) => t.id == 't4');
      if (track4Statuses.isEmpty || track4Statuses.last != t4.status) {
        track4Statuses.add(t4.status);
      }
    });

    // Run batch alignment on the collection
    await wm.runBatch(col);

    // Verify both Track 3 and Track 4 were aligned
    expect(fakeAligner.alignedAudios.length, 2);

    // Verify Track 4 transitioned through processing to done
    expect(track4Statuses, contains(AlignmentStatus.processing));
    expect(track4Statuses.last, AlignmentStatus.done);

    // Verify all 4 tracks in in-memory collection are done
    expect(col.tracks[0].status, AlignmentStatus.done);
    expect(col.tracks[1].status, AlignmentStatus.done);
    expect(col.tracks[2].status, AlignmentStatus.done);
    expect(col.tracks[3].status, AlignmentStatus.done);

    // Verify collection.json on disk was saved with Track 4 as done
    final colFile = File(p.join(projectDir, 'collections', col.folderName, 'collection.json'));
    final colContent = jsonDecode(await colFile.readAsString());
    final tracksJson = (colContent['tracks'] as List);
    expect(tracksJson[2]['status'], AlignmentStatus.done.index);
    expect(tracksJson[3]['status'], AlignmentStatus.done.index);

    // Verify alignment json files exist on disk
    final t3Out = File(p.join(projectDir, 'collections', col.folderName, 'alignments', 'track_03_timing.json'));
    final t4Out = File(p.join(projectDir, 'collections', col.folderName, 'alignments', 'track_04_timing.json'));
    expect(await t3Out.exists(), isTrue);
    expect(await t4Out.exists(), isTrue);

    wm.dispose();
  });
}
