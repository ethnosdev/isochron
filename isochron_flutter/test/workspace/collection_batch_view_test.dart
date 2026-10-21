import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:isochron_flutter/ui/workspace/views/collection_batch_view.dart';
import 'package:isochron_flutter/ui/workspace/workspace_manager.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tempDir;
  late Project project;
  late Collection collection;
  late Track trackAligned;
  late Track trackPending;
  late Track trackReviewed;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await UserSettingsService().init();

    tempDir = await Directory.systemTemp.createTemp('batch_view_test_');

    trackAligned = Track(
      id: 't_aligned',
      collectionId: 'c1',
      name: 'Chapter 01',
      outputFilename: 'ch01_timing.json',
      status: AlignmentStatus.aligned,
    );

    trackPending = Track(
      id: 't_pending',
      collectionId: 'c1',
      name: 'Chapter 02',
      outputFilename: 'ch02_timing.json',
      status: AlignmentStatus.pending,
    );

    trackReviewed = Track(
      id: 't_reviewed',
      collectionId: 'c1',
      name: 'Chapter 03',
      outputFilename: 'ch03_timing.json',
      status: AlignmentStatus.reviewed,
    );

    collection = Collection(
      id: 'c1',
      name: 'Gospel of Mark',
      tracks: [trackAligned, trackPending, trackReviewed],
    );

    project = Project(
      id: 'p1',
      name: 'Test Project',
      directoryPath: tempDir.path,
      collections: [collection],
    );

    // Create alignment file for trackAligned and trackReviewed
    final alignDir = Directory(
      p.join(tempDir.path, 'collections', collection.folderName, 'alignments'),
    );
    await alignDir.create(recursive: true);

    final fAligned = File(p.join(alignDir.path, trackAligned.outputFilename));
    await fAligned.writeAsString(jsonEncode([
      {'index': 0, 'id': '1:1', 'start': 0.0, 'end': 3.0},
    ]));

    final fReviewed = File(p.join(alignDir.path, trackReviewed.outputFilename));
    await fReviewed.writeAsString(jsonEncode([
      {'index': 0, 'id': '3:1', 'start': 0.0, 'end': 2.5},
    ]));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('appkit_ui_element_colors'),
      (call) async {
        if (call.method == 'getColorComponents') {
          return {
            'hueComponent': 0.5,
            'redComponent': 0.0,
            'greenComponent': 0.5,
            'blueComponent': 1.0,
            'alphaComponent': 1.0,
          };
        }
        return null;
      },
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('appkit_ui_element_colors'),
      null,
    );
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Widget createTestWidget({
    bool isRunning = false,
    void Function(Track track, AlignmentStatus newStatus)? onTrackStatusChanged,
    void Function(Track track)? onOpenTrack,
    VoidCallback? onImportFiles,
    VoidCallback? onDeleteCollection,
  }) {
    return MacosApp(
      home: MacosWindow(
        child: CollectionBatchView(
          collection: collection,
          project: project,
          isRunning: isRunning,
          status: 'Ready',
          progress: 0.0,
          onRunBatch: () {},
          onStopBatch: () {},
          onChanged: () {},
          onImportFiles: onImportFiles ?? () {},
          onOpenTrack: onOpenTrack ?? (_) {},
          onHealBrokenLinks: () {},
          onDeleteCollection: onDeleteCollection,
          onTrackStatusChanged: onTrackStatusChanged,
        ),
      ),
    );
  }

  group('CollectionBatchView Label & Interaction Tests', () {
    testWidgets('displays ALIGNED label instead of DONE in header and track rows', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Check summary header text
      expect(
        find.text('3 tracks • 1 reviewed, 1 aligned, 1 pending'),
        findsOneWidget,
      );

      // Verify no "DONE" text is present
      expect(find.text('DONE'), findsNothing);

      // Verify "ALIGNED", "PENDING", and "REVIEWED" status badges are visible
      expect(find.text('ALIGNED'), findsOneWidget);
      expect(find.text('PENDING'), findsOneWidget);
      expect(find.text('REVIEWED'), findsOneWidget);
    });

    testWidgets('clicking status badge opens popup menu and does not trigger onOpenTrack', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      bool openTrackCalled = false;
      await tester.pumpWidget(createTestWidget(
        onOpenTrack: (_) => openTrackCalled = true,
      ));
      await tester.pumpAndSettle();

      // Tap the ALIGNED status pill
      final alignedFinder = find.text('ALIGNED');
      expect(alignedFinder, findsOneWidget);
      await tester.tap(alignedFinder);
      await tester.pumpAndSettle();

      // Ensure onOpenTrack was NOT invoked when clicking the badge
      expect(openTrackCalled, isFalse);

      // Context menu items should appear
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Aligned'), findsOneWidget);
      expect(find.text('Reviewed'), findsOneWidget);
    });

    testWidgets('status menu disables Aligned and Reviewed for tracks without alignment data', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // trackPending has no alignment file on disk
      final pendingFinder = find.text('PENDING');
      await tester.tap(pendingFinder);
      await tester.pumpAndSettle();

      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Aligned'), findsOneWidget);
      expect(find.text('Reviewed'), findsOneWidget);

      // Tapping "Aligned" or "Reviewed" on pending track without data should do nothing
      // (items are disabled)
      await tester.tap(find.text('Aligned'));
      await tester.pumpAndSettle();

      // Track status should still be pending
      expect(trackPending.status, AlignmentStatus.pending);
    });

    testWidgets('selecting a status in menu calls onTrackStatusChanged and updates status', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      Track? updatedTrack;
      AlignmentStatus? updatedStatus;

      await tester.pumpWidget(createTestWidget(
        onTrackStatusChanged: (track, status) {
          updatedTrack = track;
          updatedStatus = status;
        },
      ));
      await tester.pumpAndSettle();

      // Tap ALIGNED badge and select "Reviewed"
      await tester.tap(find.text('ALIGNED'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reviewed'));
      await tester.pumpAndSettle();

      expect(updatedTrack?.id, trackAligned.id);
      expect(updatedStatus, AlignmentStatus.reviewed);
      expect(trackAligned.status, AlignmentStatus.reviewed);
    });

    testWidgets('status badge is non-interactive while isRunning is true', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget(isRunning: true));
      await tester.pumpAndSettle();

      // Tapping badge while isRunning should not open menu
      await tester.tap(find.text('ALIGNED'));
      await tester.pumpAndSettle();

      expect(find.text('Pending'), findsNothing);
      expect(find.text('Reviewed'), findsNothing);
    });

    testWidgets('header renders prominent Run button and More menu, but no standalone secondary buttons', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // "Run Alignment on All" should be present as prominent button
      expect(find.text('Run Alignment on All'), findsOneWidget);

      // More menu icon should be present
      final moreFinder = find.byWidgetPredicate(
        (w) => w is MacosIcon && w.icon == CupertinoIcons.ellipsis_circle,
      );
      expect(moreFinder, findsOneWidget);

      // Standalone secondary buttons should NOT be in the header row
      expect(find.text('Manage Track Pairings...'), findsNothing);
      expect(find.text('Clear All Tracks...'), findsNothing);
      expect(find.text('Export Timings...'), findsNothing);
    });

    testWidgets('clicking More button opens menu with pairings, export, rename, and delete', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      bool importFilesCalled = false;

      await tester.pumpWidget(createTestWidget(
        onImportFiles: () => importFilesCalled = true,
        onDeleteCollection: () {},
      ));
      await tester.pumpAndSettle();

      // Click the More button
      final moreFinder = find.byWidgetPredicate(
        (w) => w is MacosIcon && w.icon == CupertinoIcons.ellipsis_circle,
      );
      expect(moreFinder, findsOneWidget);
      await tester.tap(moreFinder);
      await tester.pumpAndSettle();

      // Verify menu items
      expect(find.text('Manage Track Pairings...'), findsOneWidget);
      expect(find.text('Export Timings...'), findsOneWidget);
      expect(find.text('Rename Collection...'), findsOneWidget);
      expect(find.text('Delete Collection'), findsOneWidget);

      // Tap Manage Track Pairings...
      await tester.tap(find.text('Manage Track Pairings...'));
      await tester.pumpAndSettle();
      expect(importFilesCalled, isTrue);
    });

    testWidgets('clicking Delete Collection in More menu prompts confirmation and invokes callback', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      bool deleteCalled = false;

      await tester.pumpWidget(createTestWidget(
        onDeleteCollection: () => deleteCalled = true,
      ));
      await tester.pumpAndSettle();

      final moreFinder = find.byWidgetPredicate(
        (w) => w is MacosIcon && w.icon == CupertinoIcons.ellipsis_circle,
      );
      await tester.tap(moreFinder);
      await tester.pumpAndSettle();

      // Tap Delete Collection
      await tester.tap(find.text('Delete Collection'));
      await tester.pumpAndSettle();

      // CupertinoAlertDialog should appear
      expect(find.text('Delete Collection?'), findsOneWidget);

      // Tap Delete in dialog
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(deleteCalled, isTrue);
    });

    testWidgets('responsive layout renders gracefully on narrow widths without overflowing', (tester) async {
      // Narrow width < 550
      tester.view.physicalSize = const Size(480, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Verify elements render without throwing RenderFlex overflow
      expect(find.text('Run Alignment on All'), findsOneWidget);
      final moreFinder = find.byWidgetPredicate(
        (w) => w is MacosIcon && w.icon == CupertinoIcons.ellipsis_circle,
      );
      expect(moreFinder, findsOneWidget);
      expect(find.text('ALIGNED'), findsOneWidget);
    });
  });

  group('WorkspaceManager updateTrackStatus tests', () {
    test('updates track status and persists to collection.json', () async {
      final wm = WorkspaceManager();
      final projectDir = p.join(tempDir.path, 'TestWMProject');
      await wm.createProject(projectDir, 'TestWMProject');

      final col = wm.project!.collections.first;
      final track = Track(
        id: 't_wm',
        collectionId: col.id,
        name: 'WM Track',
        outputFilename: 'wm_timing.json',
        status: AlignmentStatus.aligned,
      );
      col.tracks.add(track);
      await col.saveTracks(projectDir);

      bool notified = false;
      wm.addListener(() => notified = true);

      await wm.updateTrackStatus(track, col, AlignmentStatus.reviewed);

      expect(notified, isTrue);
      expect(track.status, AlignmentStatus.reviewed);

      // Verify on disk
      final colFile = File(
        p.join(projectDir, 'collections', col.folderName, 'collection.json'),
      );
      final colJson = jsonDecode(await colFile.readAsString());
      final savedTracks = colJson['tracks'] as List;
      expect(savedTracks.first['status'], AlignmentStatus.reviewed.index);

      wm.dispose();
    });
  });
}
