import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isochron_flutter/ui/workspace/components/track_pairing_wizard.dart';
import 'package:macos_ui/macos_ui.dart';

Widget _buildTestApp(Widget child) {
  return MacosApp(
    home: MacosWindow(
      child: ContentArea(
        builder: (context, _) => child,
      ),
    ),
  );
}

void main() {
  group('TrackPairingWizard Widget Tests', () {
    testWidgets('renders wizard with initial files and shows paired rows',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final audio = [
        '/test/BSB_40_Mat_001.mp3',
        '/test/BSB_40_Mat_002.mp3',
      ];
      final text = [
        '/test/BSB_40_Mat_001.txt',
        '/test/BSB_40_Mat_002.txt',
      ];

      await tester.pumpWidget(
        _buildTestApp(
          TrackPairingWizard(
            collectionName: 'NT',
            initialAudioFiles: audio,
            initialTextFiles: text,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Add & Pair Media — NT'), findsOneWidget);
      expect(find.text('Audio Files'), findsOneWidget);
      expect(find.text('Transcripts'), findsOneWidget);
      expect(find.text('2 Paired'), findsOneWidget);
      expect(find.text('Import 2 Tracks'), findsOneWidget);

      expect(find.text('BSB_40_Mat_001.mp3'), findsOneWidget);
      expect(find.text('BSB_40_Mat_001.txt'), findsOneWidget);
    });

    testWidgets('empty state renders when no files are provided',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _buildTestApp(
          const TrackPairingWizard(
            collectionName: 'Main',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Add & Pair Media — Main'), findsOneWidget);
      expect(
        find.text('Select audio and transcript files above to preview pairings.'),
        findsOneWidget,
      );
      expect(find.text('Import Tracks'), findsOneWidget);
    });

    testWidgets('shows warning chip when text is missing', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _buildTestApp(
          const TrackPairingWizard(
            collectionName: 'Main',
            initialAudioFiles: [
              '/test/track_01.mp3',
              '/test/track_02.mp3',
            ],
            initialTextFiles: [
              '/test/track_01.txt',
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 Paired'), findsOneWidget);
      expect(find.text('1 Missing Transcript'), findsOneWidget);
      expect(find.text('(missing transcript)'), findsOneWidget);
      expect(find.text('Import 2 Tracks'), findsOneWidget);
    });

    testWidgets('inserting gap shifts transcript downwards', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _buildTestApp(
          const TrackPairingWizard(
            collectionName: 'Main',
            initialAudioFiles: [
              '/test/a1.mp3',
              '/test/a2.mp3',
            ],
            initialTextFiles: [
              '/test/t1.txt',
              '/test/t2.txt',
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 Paired'), findsOneWidget);

      // Find first "insert gap" button (arrow_down_to_line)
      final gapButton = find.byWidgetPredicate(
        (w) => w is MacosIcon && w.icon == CupertinoIcons.arrow_down_to_line,
      ).first;
      await tester.tap(gapButton);
      await tester.pumpAndSettle();

      // Now row 0 transcript should be missing, shifting t1 to row 1, and t2 to row 2
      expect(find.text('(missing transcript)'), findsOneWidget);
      expect(find.text('Import 3 Tracks'), findsOneWidget);
    });
  });
}
