import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isochron_flutter/services/export_service.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:isochron_flutter/ui/workspace/components/group_export_dialog.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late Project project;
  late Collection collection;
  late Track track1;
  late Track track2;
  late Track pendingTrack;

  Future<void> writeTrackOutput(
    Track track,
    List<Map<String, dynamic>> entries,
  ) async {
    final colDir = Directory(
      p.join(tempDir.path, 'collections', collection.folderName, 'alignments'),
    );
    await colDir.create(recursive: true);
    final file = File(p.join(colDir.path, track.outputFilename));
    await file.writeAsString(jsonEncode(entries));
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('group_export_dialog_test_');

    track1 = Track(
      id: 'track_1',
      collectionId: 'col_1',
      name: 'Track 1',
      audioPath: '/audio/track1.wav',
      textPath: '/text/TH-01-GEN-01.txt',
      outputFilename: 'track_1.json',
      status: AlignmentStatus.done,
    );

    track2 = Track(
      id: 'track_2',
      collectionId: 'col_1',
      name: 'Track 2',
      audioPath: '/audio/track2.wav',
      textPath: '/text/TH-01-GEN-02.txt',
      outputFilename: 'track_2.json',
      status: AlignmentStatus.reviewed,
    );

    pendingTrack = Track(
      id: 'track_pending',
      collectionId: 'col_1',
      name: 'Pending Track',
      audioPath: '/audio/rec03.wav',
      textPath: '/text/TH-01-GEN-03.txt',
      outputFilename: 'track_3.json',
      status: AlignmentStatus.pending,
    );

    collection = Collection(
      id: 'col_1',
      name: 'Genesis Collection',
      tracks: [track1, track2, pendingTrack],
    );

    project = Project(
      id: 'proj_1',
      name: 'My Holy Bible',
      directoryPath: tempDir.path,
      collections: [collection],
    );

    await writeTrackOutput(track1, [
      {'index': 0, 'id': '1:1', 'start': 0.0, 'end': 3.5},
      {'index': 1, 'id': '1:2', 'start': 3.5, 'end': 7.0},
    ]);

    await writeTrackOutput(track2, [
      {'index': 0, 'id': '2:1', 'start': 0.0, 'end': 4.2},
      {'index': 1, 'id': '2:2', 'start': 4.2, 'end': 8.8},
    ]);

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

  Widget buildLauncherWidget(
    WidgetTester tester, {
    Collection? targetCollection,
    DirectoryPickerFn? directoryPicker,
    FileSaverFn? fileSaver,
  }) {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    return MacosApp(
      home: MacosWindow(
        child: Builder(
          builder: (ctx) => PushButton(
            controlSize: ControlSize.large,
            onPressed: () => GroupExportDialog.show(
              ctx,
              project: project,
              collection: targetCollection,
              directoryPicker: directoryPicker,
              fileSaver: fileSaver,
            ),
            child: const Text('Open Export Sheet'),
          ),
        ),
      ),
    );
  }

  testWidgets('renders collection export dialog with readiness counts', (
    tester,
  ) async {
    await tester.pumpWidget(buildLauncherWidget(tester, targetCollection: collection));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Export Sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Export Collection Timings'), findsOneWidget);
    expect(
      find.text('Export phrase timings for collection "Genesis Collection".'),
      findsOneWidget,
    );
    expect(
      find.text(
        '2 of 3 track(s) are ready to export. 1 unaligned track(s) will be skipped.',
      ),
      findsOneWidget,
    );

    // Verify both mode options are present
    expect(find.text('Separate files'), findsOneWidget);
    expect(find.text('Single file'), findsOneWidget);

    // Verify buttons
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Export...'), findsOneWidget);
  });

  testWidgets('renders project export dialog title and subtitle', (
    tester,
  ) async {
    await tester.pumpWidget(buildLauncherWidget(tester, targetCollection: null));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Export Sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Export Project Timings'), findsOneWidget);
    expect(
      find.text(
        'Export phrase timings for all collections in "My Holy Bible".',
      ),
      findsOneWidget,
    );
  });

  testWidgets('disables export when 0 tracks are ready', (tester) async {
    final emptyCol = Collection(
      id: 'empty_col',
      name: 'Empty Col',
      tracks: [pendingTrack],
    );

    await tester.pumpWidget(buildLauncherWidget(tester, targetCollection: emptyCol));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Export Sheet'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'None of the 1 track(s) have finished alignment. Run alignment on tracks before exporting.',
      ),
      findsOneWidget,
    );

    // PushButton for Export... should be disabled (onPressed is null)
    final exportBtn = tester.widget<PushButton>(
      find.widgetWithText(PushButton, 'Export...'),
    );
    expect(exportBtn.onPressed, isNull);
  });

  testWidgets('switches selected export mode when tapped', (tester) async {
    await tester.pumpWidget(buildLauncherWidget(tester, targetCollection: collection));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Export Sheet'));
    await tester.pumpAndSettle();

    final singleFileFinder = find.text('Single file');
    await tester.tap(singleFileFinder);
    await tester.pumpAndSettle();

    // Verify radio button update
    final radioButtons = tester.widgetList<MacosRadioButton<GroupExportMode>>(
      find.byType(MacosRadioButton<GroupExportMode>),
    );
    for (final radio in radioButtons) {
      expect(radio.groupValue, GroupExportMode.singleFile);
    }
  });

  testWidgets('executes separateFiles export and shows success alert', (
    tester,
  ) async {
    final exportDir =
        Directory(p.join(tempDir.path, 'exported_chapters'))..createSync();

    String? pickedDialogTitle;
    await tester.pumpWidget(
      buildLauncherWidget(tester, 
        targetCollection: collection,
        directoryPicker: ({dialogTitle, initialDirectory}) async {
          pickedDialogTitle = dialogTitle;
          return exportDir.path;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Export Sheet'));
    await tester.pumpAndSettle();

    // Tap Export...
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(PushButton, 'Export...'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(pickedDialogTitle, 'Select Destination Folder for Export');

    // Check exported files exist
    final files = exportDir.listSync().whereType<File>().toList();
    expect(files.length, 2);
    final fileNames = files.map((f) => p.basename(f.path)).toSet();
    expect(fileNames.contains('TH-01-GEN-01-timing.txt'), isTrue);
    expect(fileNames.contains('TH-01-GEN-02-timing.txt'), isTrue);

    // Success alert should be displayed
    expect(find.text('Export Complete'), findsOneWidget);
    expect(
      find.text('Successfully exported 2 timing file(s) to:\n${exportDir.path}'),
      findsOneWidget,
    );

    // Dismiss alert dialog
    await tester.tap(find.widgetWithText(PushButton, 'OK'));
    await tester.pumpAndSettle();
    expect(find.text('Export Complete'), findsNothing);
  });

  testWidgets('executes singleFile export and shows success alert', (
    tester,
  ) async {
    final saveFileTarget = p.join(tempDir.path, 'output-divided.txt');
    String? capturedFileName;

    await tester.pumpWidget(
      buildLauncherWidget(tester, 
        targetCollection: collection,
        fileSaver: ({
          allowedExtensions,
          dialogTitle,
          fileName,
          initialDirectory,
          type = FileType.any,
        }) async {
          capturedFileName = fileName;
          return saveFileTarget;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Export Sheet'));
    await tester.pumpAndSettle();

    // Select single file mode
    await tester.tap(find.text('Single file'));
    await tester.pumpAndSettle();

    // Tap Export...
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(PushButton, 'Export...'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(capturedFileName, 'Genesis_Collection-timing.txt');

    final exportedFile = File(saveFileTarget);
    expect(exportedFile.existsSync(), isTrue);
    final content = exportedFile.readAsStringSync();
    expect(content, contains('\\id GEN\n\\c 01\n\\level phrase\n'));
    expect(content, contains('\\id GEN\n\\c 02\n\\level phrase\n'));

    expect(find.text('Export Complete'), findsOneWidget);
    await tester.tap(find.widgetWithText(PushButton, 'OK'));
    await tester.pumpAndSettle();
  });
}
