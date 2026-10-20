import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isochron_cli/isochron_cli.dart';
import 'package:isochron_flutter/services/alignment_service.dart';
import 'package:isochron_flutter/services/audio_service.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'package:isochron_flutter/ui/app_manager.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:isochron_flutter/ui/workspace/components/workspace_toolbar.dart';
import 'package:isochron_flutter/ui/workspace/models/workspace_models.dart';
import 'package:isochron_flutter/ui/workspace/workspace_manager.dart';
import 'package:just_audio/just_audio.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class FakeAudioService extends AudioService {
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<PlayerState> get stateStream => const Stream.empty();
  @override
  Duration? get duration => Duration.zero;
  @override
  Future<Duration> load(String path) async => Duration.zero;
  @override
  Future<void> pause() async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  void dispose() {}
}

class FakeAlignmentService extends AlignmentService {
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
    return [
      Fragment(index: 0, text: 'Verse 1')..setRealTiming(start: 0.0, end: 2.0),
      Fragment(index: 1, text: 'Verse 2')..setRealTiming(start: 2.0, end: 4.0),
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await UserSettingsService().init();
    tempDir = await Directory.systemTemp.createTemp('isochron_autosave_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Auto-Save Engine Tests', () {
    test('saveProject atomically writes alignment JSON to autoSavePath', () async {
      final appManager = AppManager();
      final saveFile = File('${tempDir.path}/alignment.json');
      final frags = [
        Fragment(index: 0, text: 'Verse 1')..setRealTiming(start: 0.0, end: 2.0),
        Fragment(index: 1, text: 'Verse 2')..setRealTiming(start: 2.0, end: 4.5),
      ];

      appManager.value = appManager.value.copyWith(
        autoSavePath: saveFile.path,
        fragments: frags,
        hasUnsavedChanges: true,
      );

      await appManager.saveProject();

      expect(appManager.value.hasUnsavedChanges, isFalse);
      expect(await saveFile.exists(), isTrue);

      final content = await saveFile.readAsString();
      final List<dynamic> jsonList = jsonDecode(content);
      expect(jsonList.length, 2);
      expect(jsonList[0]['text'], 'Verse 1');
      expect(jsonList[1]['text'], 'Verse 2');

      appManager.dispose();
    });

    test('nudgeActiveBoundary schedules 1-second debounce auto-save', () async {
      final appManager = AppManager();
      final saveFile = File('${tempDir.path}/alignment_nudge.json');
      final frags = [
        Fragment(index: 0, text: 'Verse 1')..setRealTiming(start: 1.0, end: 3.0),
      ];

      appManager.value = appManager.value.copyWith(
        audioDuration: const Duration(seconds: 10),
        autoSavePath: saveFile.path,
        fragments: frags,
        selectedFragmentIndex: 0,
      );

      appManager.nudgeActiveBoundary(0.05);
      expect(saveFile.existsSync(), isFalse);

      // Advance 500ms - still debouncing
      await Future.delayed(const Duration(milliseconds: 500));
      expect(saveFile.existsSync(), isFalse);

      // Nudge again - resets debounce timer
      appManager.nudgeActiveBoundary(0.05);
      await Future.delayed(const Duration(milliseconds: 600));
      expect(saveFile.existsSync(), isFalse);

      // Advance past 1000ms pause from last nudge
      await Future.delayed(const Duration(milliseconds: 600));
      expect(saveFile.existsSync(), isTrue);

      appManager.dispose();
    });

    test('flushPendingAutoSave immediately flushes debounce timer', () async {
      final appManager = AppManager();
      final saveFile = File('${tempDir.path}/alignment_flush.json');
      final frags = [
        Fragment(index: 0, text: 'Verse 1')..setRealTiming(start: 1.0, end: 3.0),
      ];

      appManager.value = appManager.value.copyWith(
        audioDuration: const Duration(seconds: 10),
        autoSavePath: saveFile.path,
        fragments: frags,
        selectedFragmentIndex: 0,
      );

      appManager.nudgeActiveBoundary(0.1);
      expect(saveFile.existsSync(), isFalse);

      // Flush immediately
      await appManager.flushPendingAutoSave();

      expect(saveFile.existsSync(), isTrue);
      expect(appManager.value.hasUnsavedChanges, isFalse);

      appManager.dispose();
    });

    test('markReviewedAndAdvance triggers immediate auto-save', () async {
      final appManager = AppManager();
      final saveFile = File('${tempDir.path}/alignment_reviewed.json');
      final frags = [
        Fragment(index: 0, text: 'Verse 1', status: FragmentStatus.auto)
          ..setRealTiming(start: 1.0, end: 3.0),
        Fragment(index: 1, text: 'Verse 2', status: FragmentStatus.auto)
          ..setRealTiming(start: 3.0, end: 5.0),
      ];

      appManager.value = appManager.value.copyWith(
        autoSavePath: saveFile.path,
        fragments: frags,
        selectedFragmentIndex: 0,
      );

      appManager.markReviewedAndAdvance();

      // Give async file write a tick to complete
      await Future.delayed(const Duration(milliseconds: 50));

      expect(saveFile.existsSync(), isTrue);
      expect(appManager.value.hasUnsavedChanges, isFalse);

      final content = await saveFile.readAsString();
      final List<dynamic> jsonList = jsonDecode(content);
      expect(jsonList[0]['status'], 'reviewed');

      appManager.dispose();
    });

    test('clearFragmentTiming triggers immediate auto-save', () async {
      final appManager = AppManager();
      final saveFile = File('${tempDir.path}/alignment_clear.json');
      final frags = [
        Fragment(index: 0, text: 'Verse 1')..setRealTiming(start: 1.0, end: 3.0),
      ];

      appManager.value = appManager.value.copyWith(
        autoSavePath: saveFile.path,
        fragments: frags,
        selectedFragmentIndex: 0,
      );

      appManager.clearFragmentTiming(0);

      await Future.delayed(const Duration(milliseconds: 50));

      expect(saveFile.existsSync(), isTrue);
      expect(appManager.value.hasUnsavedChanges, isFalse);

      final content = await saveFile.readAsString();
      final List<dynamic> jsonList = jsonDecode(content);
      expect(jsonList[0]['start'], -1.0);

      appManager.dispose();
    });

    test('WorkspaceManager onSaveCallback sets track status to reviewed on edits and done on alignment', () async {
      final wsManager = WorkspaceManager();
      final col = Collection(id: 'c1', name: 'Collection 1');
      final track = Track(
        id: 't1',
        collectionId: 'c1',
        name: 'Track 1',
        outputFilename: 't1.json',
      );
      col.tracks.add(track);

      final project = Project(
        id: 'p1',
        name: 'Project 1',
        directoryPath: tempDir.path,
        collections: [col],
      );

      wsManager.project = project;
      wsManager.selectedNode = TreeSelection(
        type: NodeType.track,
        collection: col,
        track: track,
      );

      // 1. Initial unedited alignment
      wsManager.homeManager.value = wsManager.homeManager.value.copyWith(
        autoSavePath: '${tempDir.path}/t1.json',
        fragments: [
          Fragment(
            index: 0,
            text: 'V1',
            status: FragmentStatus.auto,
          )..setRealTiming(start: 0.0, end: 2.0),
        ],
      );

      await wsManager.homeManager.saveProject();
      expect(track.status, AlignmentStatus.done);

      // 2. User edits verse
      wsManager.homeManager.value = wsManager.homeManager.value.copyWith(
        fragments: [
          Fragment(
            index: 0,
            text: 'V1',
            status: FragmentStatus.edited,
          )..setRealTiming(start: 0.5, end: 2.5),
        ],
      );

      await wsManager.homeManager.saveProject();
      expect(track.status, AlignmentStatus.reviewed);

      wsManager.dispose();
    });

    test('runAlignment preserves and auto-generates fragment IDs after auto-align', () async {
      final appManager = AppManager(
        audioService: FakeAudioService(),
        alignmentService: FakeAlignmentService(),
      );
      final track = Track(
        id: 't1',
        name: 'BSB_40_Mat_001',
        outputFilename: 't1.json',
      );
      final col = Collection(id: 'c1', name: 'NT', tracks: [track]);
      final project = Project(
        id: 'p1',
        name: 'BSB',
        directoryPath: tempDir.path,
        collections: [col],
      );

      final audioFile = File('${tempDir.path}/audio.wav');
      await audioFile.writeAsString('RIFF dummy');
      final textFile = File('${tempDir.path}/text.txt');
      await textFile.writeAsString('Line 1\nLine 2');
      final jsonFile = File('${tempDir.path}/t1.json');

      appManager.currentTrack = track;
      appManager.currentProject = project;

      // Existing fragments had IDs generated or user-provided
      appManager.value = appManager.value.copyWith(
        audioPath: audioFile.path,
        textPath: textFile.path,
        autoSavePath: jsonFile.path,
        fragments: [
          Fragment(index: 0, id: '40001001', text: 'Line 1'),
          Fragment(index: 1, id: '40001002', text: 'Line 2'),
        ],
      );

      await appManager.runAlignment(trackId: 't1');

      expect(appManager.value.fragments.length, 2);
      expect(appManager.value.fragments[0].id, '40001001');
      expect(appManager.value.fragments[1].id, '40001002');

      appManager.dispose();
    });

    test('loadTrack auto-populates missing IDs for existing alignment JSON', () async {
      final appManager = AppManager(
        audioService: FakeAudioService(),
        alignmentService: FakeAlignmentService(),
      );
      final col = Collection(id: 'c1', name: 'NT');
      final track = Track(
        id: 't1',
        collectionId: 'c1',
        name: 'BSB_40_Mat_001',
        audioPath: 'audio.wav',
        textPath: 'text.txt',
        outputFilename: 't1.json',
      );
      col.tracks.add(track);
      final project = Project(
        id: 'p1',
        name: 'BSB',
        directoryPath: tempDir.path,
        collections: [col],
      );

      final audioDir = Directory(p.join(tempDir.path, 'collections', 'NT', 'audio'))..createSync(recursive: true);
      final textDir = Directory(p.join(tempDir.path, 'collections', 'NT', 'text'))..createSync(recursive: true);
      final alignDir = Directory(p.join(tempDir.path, 'collections', 'NT', 'alignments'))..createSync(recursive: true);

      File(p.join(audioDir.path, 'audio.wav')).writeAsStringSync('RIFF');
      File(p.join(textDir.path, 'text.txt')).writeAsStringSync('Verse 1\nVerse 2');

      // Write an alignment JSON where ID was null
      final jsonFile = File(p.join(alignDir.path, 't1.json'));
      jsonFile.writeAsStringSync(jsonEncode([
        {'index': 0, 'text': 'Verse 1', 'start': 0.0, 'end': 1.0, 'id': null},
        {'index': 1, 'text': 'Verse 2', 'start': 1.0, 'end': 2.0, 'id': null},
      ]));

      await appManager.loadTrack(track, project);

      expect(appManager.value.fragments.length, 2);
      expect(appManager.value.fragments[0].id, '40001001');
      expect(appManager.value.fragments[1].id, '40001002');

      appManager.dispose();
    });

    testWidgets('Toolbar has Auto-Align and no Save button', (tester) async {
      final wsManager = WorkspaceManager();
      final track = Track(id: 't1', name: 'Track 1', outputFilename: 't1.json');
      final col = Collection(id: 'c1', name: 'Col 1', tracks: [track]);
      final project = Project(id: 'p1', name: 'Proj', directoryPath: tempDir.path, collections: [col]);
      wsManager.project = project;
      wsManager.selectedNode = TreeSelection(type: NodeType.track, collection: col, track: track);

      await tester.pumpWidget(_ToolbarTestHost(manager: wsManager));
      await tester.pumpAndSettle();

      expect(find.text('Save'), findsNothing);
      expect(find.text('Auto-Align'), findsOneWidget);

      wsManager.dispose();
    });

    testWidgets('Auto-Align on track with user edits shows 3-choice overwrite dialog', (tester) async {
      final wsManager = WorkspaceManager();
      final track = Track(id: 't1', name: 'Track 1', outputFilename: 't1.json');
      final col = Collection(id: 'c1', name: 'Col 1', tracks: [track]);
      final project = Project(id: 'p1', name: 'Proj', directoryPath: tempDir.path, collections: [col]);
      wsManager.project = project;
      wsManager.selectedNode = TreeSelection(type: NodeType.track, collection: col, track: track);

      wsManager.homeManager.value = wsManager.homeManager.value.copyWith(
        fragments: [
          Fragment(index: 0, text: 'V1', status: FragmentStatus.edited)
            ..setRealTiming(start: 1.0, end: 3.0),
        ],
      );

      await tester.pumpWidget(_ToolbarTestHost(manager: wsManager));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is MacosIcon && w.icon == CupertinoIcons.wand_rays,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Re-align Track?'), findsOneWidget);
      expect(find.text('Keep My Edits'), findsOneWidget);
      expect(find.text('Overwrite All'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.text('Cancel'), warnIfMissed: false);
      await tester.pumpAndSettle();

      wsManager.dispose();
    });

    testWidgets('Auto-Align on track with unedited alignment shows Overwrite confirmation', (tester) async {
      final wsManager = WorkspaceManager();
      final track = Track(id: 't1', name: 'Track 1', outputFilename: 't1.json');
      final col = Collection(id: 'c1', name: 'Col 1', tracks: [track]);
      final project = Project(id: 'p1', name: 'Proj', directoryPath: tempDir.path, collections: [col]);
      wsManager.project = project;
      wsManager.selectedNode = TreeSelection(type: NodeType.track, collection: col, track: track);

      wsManager.homeManager.value = wsManager.homeManager.value.copyWith(
        fragments: [
          Fragment(index: 0, text: 'V1', status: FragmentStatus.auto)
            ..setRealTiming(start: 1.0, end: 3.0),
        ],
      );

      await tester.pumpWidget(_ToolbarTestHost(manager: wsManager));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is MacosIcon && w.icon == CupertinoIcons.wand_rays,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Re-align Track?'), findsOneWidget);
      expect(find.text('Overwrite'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Keep My Edits'), findsNothing);

      // Dismiss dialog
      await tester.tap(find.text('Cancel'), warnIfMissed: false);
      await tester.pumpAndSettle();

      wsManager.dispose();
    });
  });
}

class _ToolbarTestHost extends StatelessWidget {
  final WorkspaceManager manager;
  const _ToolbarTestHost({required this.manager});

  @override
  Widget build(BuildContext context) {
    return MacosApp(
      home: Builder(
        builder: (innerContext) {
          return MacosWindow(
            child: MacosScaffold(
              toolBar: buildWorkspaceToolbar(innerContext, manager),
              children: const [
                ContentArea(builder: _dummyBuilder),
              ],
            ),
          );
        },
      ),
    );
  }

  static Widget _dummyBuilder(BuildContext context, ScrollController? controller) {
    return const SizedBox();
  }
}
