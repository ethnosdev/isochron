import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:isochron_flutter/ui/workspace/views/project_settings_view.dart';
import 'package:isochron_flutter/ui/workspace/workspace_manager.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProjectSettingsView File Management Tests', () {
    late Directory tempProjectDir;
    late Directory tempExternalDir;
    late WorkspaceManager manager;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await UserSettingsService().init();
      tempProjectDir = await Directory.systemTemp.createTemp('isochron_settings_proj_');
      tempExternalDir = await Directory.systemTemp.createTemp('isochron_settings_ext_');
      manager = WorkspaceManager();

      await manager.createProject(
        tempProjectDir.path,
        'TestProject',
        firstCollectionName: 'Main',
        copyMediaIntoProject: false,
      );

      final col = manager.project!.collections.first;

      final extAudio = File(p.join(tempExternalDir.path, 'audio_1.mp3'));
      await extAudio.writeAsString('audio');
      final extText = File(p.join(tempExternalDir.path, 'text_1.txt'));
      await extText.writeAsString('text');

      final track = Track(
        id: 'track-1',
        name: 'Track 1',
        audioPath: extAudio.path,
        textPath: extText.path,
        outputFilename: 'track_1.json',
      );
      col.tracks.add(track);
      await col.saveTracks(tempProjectDir.path);
    });

    tearDown(() async {
      if (tempProjectDir.existsSync()) {
        tempProjectDir.deleteSync(recursive: true);
      }
      if (tempExternalDir.existsSync()) {
        tempExternalDir.deleteSync(recursive: true);
      }
    });

    testWidgets('shows consolidate dialog with concise "Copy Files" and "Don\'t Copy" buttons', (tester) async {
      final oldOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('overflowed')) return;
        oldOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = oldOnError);

      await tester.pumpWidget(
        MacosApp(
          home: MacosWindow(
            child: ProjectSettingsView(
              project: manager.project!,
              manager: manager,
              onSaved: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the checkbox for copy imported media
      final checkboxFinder = find.byType(MacosCheckbox);
      expect(checkboxFinder, findsOneWidget);

      // Tap checkbox
      await tester.tap(checkboxFinder);
      await tester.pumpAndSettle();

      // Alert dialog should appear with concise labels
      expect(find.text("Consolidate Project Media?"), findsOneWidget);
      expect(find.text("Copy Files"), findsOneWidget);
      expect(find.text("Don't Copy"), findsOneWidget);
      expect(find.text("Copy Existing Files"), findsNothing);
      expect(find.text("Only Future Imports"), findsNothing);

      // Verify buttons are PushButtons with large control size
      final primaryButton = tester.widget<PushButton>(
        find.widgetWithText(PushButton, "Copy Files"),
      );
      expect(primaryButton.controlSize, ControlSize.large);

      final secondaryButton = tester.widget<PushButton>(
        find.widgetWithText(PushButton, "Don't Copy"),
      );
      expect(secondaryButton.controlSize, ControlSize.large);
      expect(secondaryButton.secondary, isTrue);

      // Tapping "Don't Copy" dismisses the dialog and preserves checkbox state
      await tester.tap(find.text("Don't Copy"));
      await tester.pumpAndSettle();

      expect(find.text("Consolidate Project Media?"), findsNothing);
      expect(manager.project!.copyMediaIntoProject, isTrue);
      // Media remains external
      expect(manager.hasExternalMedia(), isTrue);
    });
  });
}
