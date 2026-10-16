import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isochron_cli/isochron_cli.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'package:isochron_flutter/ui/app_manager.dart';
import 'package:isochron_flutter/ui/editor/studio_editor.dart';
import 'package:isochron_flutter/ui/models/app_state.dart';
import 'package:isochron_flutter/ui/waveform/waveform_view.dart';
import 'package:just_waveform/just_waveform.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await UserSettingsService().init();
  });

  Waveform createMockWaveform() {
    return Waveform(
      version: 1,
      flags: 0,
      sampleRate: 44100,
      samplesPerPixel: 100,
      length: 100,
      data: List.filled(200, 0),
    );
  }

  group('WaveformView.calculateCenterOffset', () {
    test('calculates correct center offset at 1x zoom', () {
      // 100s audio, viewport 1000px, 1x zoom
      // anchorTime = 50s -> targetPixel = 0.5 * 1000 + 40 = 540
      // centerOffset = 540 - 500 = 40
      final offset = WaveformView.calculateCenterOffset(
        anchorTime: 50.0,
        totalDurationSeconds: 100.0,
        viewportWidth: 1000.0,
        zoomLevel: 1.0,
      );
      expect(offset, 40.0);
    });

    test('calculates correct center offset at 10x zoom', () {
      // 100s audio, viewport 1000px, 10x zoom -> contentWidth = 10,000
      // anchorTime = 50s -> targetPixel = 0.5 * 10000 + 40 = 5040
      // centerOffset = 5040 - 500 = 4540
      final offset = WaveformView.calculateCenterOffset(
        anchorTime: 50.0,
        totalDurationSeconds: 100.0,
        viewportWidth: 1000.0,
        zoomLevel: 10.0,
      );
      expect(offset, 4540.0);
    });

    test('returns 0 when totalDurationSeconds <= 0', () {
      final offset = WaveformView.calculateCenterOffset(
        anchorTime: 10.0,
        totalDurationSeconds: 0.0,
        viewportWidth: 1000.0,
        zoomLevel: 1.0,
      );
      expect(offset, 0.0);
    });

    test('calculates correct offset at start of audio', () {
      // anchorTime = 0s -> targetPixel = 40
      // centerOffset = 40 - 500 = -460
      final offset = WaveformView.calculateCenterOffset(
        anchorTime: 0.0,
        totalDurationSeconds: 100.0,
        viewportWidth: 1000.0,
        zoomLevel: 5.0,
      );
      expect(offset, -460.0);
    });
  });

  group('WaveformView view movement during timing edits and playback', () {
    testWidgets('does not recenter the view when selectedFragmentIndex changes', (tester) async {
      final scrollController = ScrollController();
      final controller = AppManager();
      final playbackNotifier = ValueNotifier<Duration>(Duration.zero);
      final waveform = createMockWaveform();

      final fragments = [
        Fragment(index: 0, text: 'Verse 1')..setRealTiming(start: 0.0, end: 10.0),
        Fragment(index: 1, text: 'Verse 2')..setRealTiming(start: 10.0, end: 50.0),
        Fragment(index: 2, text: 'Verse 3')..setRealTiming(start: 50.0, end: 100.0),
      ];

      var state = AppState(
        audioDuration: const Duration(seconds: 100),
        zoomLevel: 5.0, // 5x zoom
        waveform: waveform,
        fragments: fragments,
        selectedFragmentIndex: 0,
      );

      Widget buildWidget(AppState s) {
        return MacosApp(
          home: MacosWindow(
            child: SizedBox(
              width: 1000,
              height: 200,
              child: WaveformView(
                controller: controller,
                state: s,
                scrollController: scrollController,
                playbackNotifier: playbackNotifier,
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(buildWidget(state));
      await tester.pumpAndSettle();

      // Scroll to a custom offset
      scrollController.jumpTo(500.0);
      await tester.pumpAndSettle();
      expect(scrollController.offset, 500.0);

      // Now update selectedFragmentIndex to 2 (Verse 3)
      state = state.copyWith(selectedFragmentIndex: 2);
      await tester.pumpWidget(buildWidget(state));
      await tester.pumpAndSettle();

      // View should NOT recenter or move; it stays at 500.0
      expect(scrollController.offset, 500.0);

      scrollController.dispose();
      controller.dispose();
      playbackNotifier.dispose();
    });

    testWidgets('moves playhead to beginning of waveform view when playhead goes off screen, but not when on screen', (tester) async {
      tester.view.physicalSize = const Size(1000, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final scrollController = ScrollController();
      final controller = AppManager();
      final playbackNotifier = ValueNotifier<Duration>(Duration.zero);
      final waveform = createMockWaveform();

      final fragments = [
        Fragment(index: 0, text: 'Verse 1')..setRealTiming(start: 0.0, end: 50.0),
        Fragment(index: 1, text: 'Verse 2')..setRealTiming(start: 50.0, end: 100.0),
      ];

      final state = AppState(
        audioDuration: const Duration(seconds: 100),
        zoomLevel: 5.0, // 5x zoom => 5000px content
        waveform: waveform,
        fragments: fragments,
        selectedFragmentIndex: 0,
        isPlaying: true,
      );

      await tester.pumpWidget(
        MacosApp(
          home: MacosWindow(
            child: SizedBox(
              width: 1000,
              height: 200,
              child: WaveformView(
                controller: controller,
                state: state,
                scrollController: scrollController,
                playbackNotifier: playbackNotifier,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Position view at offset 1000 (visible range 1000 to 2000)
      scrollController.jumpTo(1000.0);
      await tester.pumpAndSettle();

      // Playhead at 25s: contentPixel = 1250, absolutePlayhead = 1290 (inside visible range [1000, 2000])
      playbackNotifier.value = const Duration(seconds: 25);
      await tester.pumpAndSettle();
      // On screen: view should NOT move
      expect(scrollController.offset, 1000.0);

      // Playhead at 50s: contentPixel = 2500, absolutePlayhead = 2540 (off screen to the right)
      playbackNotifier.value = const Duration(seconds: 50);
      await tester.pumpAndSettle();
      // Should align with beginning of waveform view (2500.0)
      expect(scrollController.offset, 2500.0);

      // Playhead jumps to 5s: contentPixel = 250, absolutePlayhead = 290 (off screen to the left)
      playbackNotifier.value = const Duration(seconds: 5);
      await tester.pumpAndSettle();
      // Should align with beginning of waveform view (250.0)
      expect(scrollController.offset, 250.0);

      scrollController.dispose();
      controller.dispose();
      playbackNotifier.dispose();
    });
  });

  group('WaveformView flick gesture momentum scrolling', () {
    testWidgets('flicking the waveform continues scrolling and slows down gradually', (tester) async {
      final scrollController = ScrollController();
      final controller = AppManager();
      final playbackNotifier = ValueNotifier<Duration>(Duration.zero);
      final waveform = createMockWaveform();

      final fragments = [
        Fragment(index: 0, text: 'Verse 1')..setRealTiming(start: 0.0, end: 100.0),
      ];

      final state = AppState(
        audioDuration: const Duration(seconds: 100),
        zoomLevel: 10.0, // 10x zoom gives plenty of scroll space
        waveform: waveform,
        fragments: fragments,
        selectedFragmentIndex: 0,
      );

      await tester.pumpWidget(
        MacosApp(
          home: MacosWindow(
            child: SizedBox(
              width: 1000,
              height: 200,
              child: WaveformView(
                controller: controller,
                state: state,
                scrollController: scrollController,
                playbackNotifier: playbackNotifier,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Start at offset 1000
      scrollController.jumpTo(1000.0);
      await tester.pumpAndSettle();
      expect(scrollController.offset, 1000.0);

      // Perform a flick/fling gesture to the left (scrolling forward/right)
      // Drag from right to left across the center of the waveform
      await tester.fling(find.byType(WaveformView), const Offset(-300, 0), 1000.0);

      // Immediately after flick, scroll offset should have increased
      final offsetAfterFling = scrollController.offset;
      expect(offsetAfterFling > 1000.0, isTrue);

      // Start ticker at t=0
      await tester.pump();

      // Over subsequent frames, ballistic simulation continues scrolling forward
      await tester.pump(const Duration(milliseconds: 100));
      final offsetFrame1 = scrollController.offset;
      expect(offsetFrame1 > offsetAfterFling, isTrue);

      await tester.pump(const Duration(milliseconds: 100));
      final offsetFrame2 = scrollController.offset;
      expect(offsetFrame2 > offsetFrame1, isTrue);

      // The delta between frames should decrease as it gradually slows down
      final delta1 = offsetFrame1 - offsetAfterFling;
      final delta2 = offsetFrame2 - offsetFrame1;
      expect(delta2 < delta1, isTrue);

      // Complete the deceleration
      await tester.pumpAndSettle();
      expect(scrollController.offset >= offsetFrame2, isTrue);

      final offsetBeforeSecondFling = scrollController.offset;
      await tester.fling(find.byType(WaveformView), const Offset(-300, 0), 1000.0);
      await tester.pumpAndSettle();
      expect(scrollController.offset > offsetBeforeSecondFling, isTrue);

      scrollController.dispose();
      controller.dispose();
      playbackNotifier.dispose();
    });

    testWidgets('touching the waveform during a fling halts scrolling immediately', (tester) async {
      final scrollController = ScrollController();
      final controller = AppManager();
      final playbackNotifier = ValueNotifier<Duration>(Duration.zero);
      final waveform = createMockWaveform();

      final fragments = [
        Fragment(index: 0, text: 'Verse 1')..setRealTiming(start: 0.0, end: 100.0),
      ];

      final state = AppState(
        audioDuration: const Duration(seconds: 100),
        zoomLevel: 10.0,
        waveform: waveform,
        fragments: fragments,
        selectedFragmentIndex: 0,
      );

      await tester.pumpWidget(
        MacosApp(
          home: MacosWindow(
            child: SizedBox(
              width: 1000,
              height: 200,
              child: WaveformView(
                controller: controller,
                state: state,
                scrollController: scrollController,
                playbackNotifier: playbackNotifier,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      scrollController.jumpTo(1000.0);
      await tester.pumpAndSettle();

      // Start a fast fling
      await tester.fling(find.byType(WaveformView), const Offset(-300, 0), 2000.0);
      await tester.pump(const Duration(milliseconds: 50));
      final offsetMidFling = scrollController.offset;

      // Touch down on the waveform to stop the fling
      final gesture = await tester.startGesture(tester.getCenter(find.byType(WaveformView)));
      await tester.pump(const Duration(milliseconds: 100));

      // Scroll position should be stationary because fling was halted
      expect(scrollController.offset, offsetMidFling);

      await gesture.up();
      await tester.pumpAndSettle();

      scrollController.dispose();
      controller.dispose();
      playbackNotifier.dispose();
    });

    testWidgets('flicking multiple times repeatedly continues scrolling smoothly without error', (tester) async {
      final scrollController = ScrollController();
      final controller = AppManager();
      final playbackNotifier = ValueNotifier<Duration>(Duration.zero);
      final waveform = createMockWaveform();

      final fragments = [
        Fragment(index: 0, text: 'Verse 1')..setRealTiming(start: 0.0, end: 100.0),
      ];

      final state = AppState(
        audioDuration: const Duration(seconds: 100),
        zoomLevel: 10.0,
        waveform: waveform,
        fragments: fragments,
        selectedFragmentIndex: 0,
      );

      await tester.pumpWidget(
        MacosApp(
          home: MacosWindow(
            child: SizedBox(
              width: 1000,
              height: 200,
              child: WaveformView(
                controller: controller,
                state: state,
                scrollController: scrollController,
                playbackNotifier: playbackNotifier,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      scrollController.jumpTo(2000.0);
      await tester.pumpAndSettle();

      // Flick 1: forward
      await tester.fling(find.byType(WaveformView), const Offset(-300, 0), 1000.0);
      await tester.pumpAndSettle();
      expect(scrollController.offset > 2000.0, isTrue);
      final offsetAfterFling1 = scrollController.offset;

      // Flick 2: forward again
      await tester.fling(find.byType(WaveformView), const Offset(-300, 0), 1000.0);
      await tester.pumpAndSettle();
      expect(scrollController.offset > offsetAfterFling1, isTrue);
      final offsetAfterFling2 = scrollController.offset;

      // Flick 3: backwards
      await tester.fling(find.byType(WaveformView), const Offset(300, 0), 1000.0);
      await tester.pumpAndSettle();
      expect(scrollController.offset < offsetAfterFling2, isTrue);

      scrollController.dispose();
      controller.dispose();
      playbackNotifier.dispose();
    });
  });

  group('StudioEditor clicking list tile item', () {
    testWidgets('clicking a list tile item visually scrolls the waveform to that position even when zoomed in', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appManager = AppManager();
      final waveform = createMockWaveform();

      final fragments = [
        Fragment(index: 0, text: 'First verse text')..setRealTiming(start: 0.0, end: 20.0),
        Fragment(index: 1, text: 'Second verse text')..setRealTiming(start: 20.0, end: 50.0),
        Fragment(index: 2, text: 'Third verse text')..setRealTiming(start: 50.0, end: 100.0),
      ];

      appManager.value = appManager.value.copyWith(
        audioDuration: const Duration(seconds: 100),
        zoomLevel: 10.0, // Zoomed in 10x
        waveform: waveform,
        fragments: fragments,
        selectedFragmentIndex: 0,
      );

      await tester.pumpWidget(
        MacosApp(
          home: MacosWindow(
            child: SizedBox(
              width: 1200,
              height: 800,
              child: StudioEditor(homeManager: appManager),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the SingleChildScrollView of the waveform
      final waveformScrollFinder = find.byType(SingleChildScrollView);
      expect(waveformScrollFinder, findsOneWidget);
      final singleScrollView = tester.widget<SingleChildScrollView>(waveformScrollFinder);
      final waveScrollController = singleScrollView.controller!;

      // Click on 'Third verse text' list tile item
      final thirdVerseFinder = find.text('Third verse text');
      expect(thirdVerseFinder, findsOneWidget);

      await tester.tap(thirdVerseFinder);
      // Wait for double tap timeout so GestureDetector fires onTap
      await tester.pump(const Duration(milliseconds: 300));
      // Start animateTo ticker
      await tester.pump();

      final viewportWidth = waveScrollController.position.viewportDimension;
      final expectedOffset = WaveformView.calculateCenterOffset(
        anchorTime: 50.0,
        totalDurationSeconds: 100.0,
        viewportWidth: viewportWidth,
        zoomLevel: 10.0,
      );

      // Verify visual animation is in progress
      await tester.pump(const Duration(milliseconds: 100));
      expect(waveScrollController.offset > 0.0, isTrue);
      expect(waveScrollController.offset < expectedOffset, isTrue);

      await tester.pumpAndSettle();
      expect(waveScrollController.offset, expectedOffset);
      expect(appManager.value.selectedFragmentIndex, 2);

      // Now scroll away manually to offset 0 while zoomed in
      waveScrollController.jumpTo(0.0);
      await tester.pumpAndSettle();
      expect(waveScrollController.offset, 0.0);

      // Click on 'Third verse text' again (already selected)
      await tester.tap(thirdVerseFinder);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Should visually scroll right back to expectedOffset even though it was already selected!
      expect(waveScrollController.offset, expectedOffset);

      appManager.dispose();
    });
  });
}
