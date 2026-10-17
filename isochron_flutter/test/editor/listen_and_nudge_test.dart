import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isochron_cli/isochron_cli.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'package:isochron_flutter/ui/app_manager.dart';
import 'package:isochron_flutter/ui/editor/studio_editor.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:isochron_flutter/ui/waveform/waveform_view.dart';
import 'package:just_waveform/just_waveform.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestAppManager extends AppManager {
  Duration? lastSoughtPosition;
  bool playCurrentFragmentCalled = false;

  @override
  void seekTo(Duration d, {bool isInternalReset = false}) {
    lastSoughtPosition = d;
  }

  @override
  void playCurrentFragment() {
    playCurrentFragmentCalled = true;
    super.playCurrentFragment();
  }
}

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

  group('Listen-and-Nudge and Quality Signals', () {
    test('Project defaults boundaryLeadInMs to 190ms', () {
      final project = Project(
        id: 'p1',
        name: 'Test Project',
        directoryPath: '/tmp/test',
      );
      expect(project.boundaryLeadInMs, 190);
    });

    test('jumpToNextFlaggedVerse navigates to next flagged fragment and wraps', () {
      final appManager = AppManager();
      final frags = [
        Fragment(index: 0, text: 'Verse 1')..setRealTiming(start: 0.0, end: 3.0),
        Fragment(index: 1, text: 'Verse 2', flags: ['not_at_pause'])..setRealTiming(start: 3.0, end: 6.0),
        Fragment(index: 2, text: 'Verse 3')..setRealTiming(start: 6.0, end: 9.0),
        Fragment(index: 3, text: 'Verse 4', flags: ['poor_text_match'])..setRealTiming(start: 9.0, end: 12.0),
      ];

      appManager.value = appManager.value.copyWith(
        fragments: frags,
        selectedFragmentIndex: 0,
      );

      // From index 0, jump should land on index 1
      appManager.jumpToNextFlaggedVerse();
      expect(appManager.value.selectedFragmentIndex, 1);

      // From index 1, jump should land on index 3
      appManager.jumpToNextFlaggedVerse();
      expect(appManager.value.selectedFragmentIndex, 3);

      // From index 3, jump should wrap around to index 1
      appManager.jumpToNextFlaggedVerse();
      expect(appManager.value.selectedFragmentIndex, 1);

      appManager.dispose();
    });

    test('markReviewedAndAdvance marks status reviewed and selects next verse', () {
      final appManager = AppManager();
      final frags = [
        Fragment(index: 0, text: 'Verse 1', status: FragmentStatus.auto)
          ..setRealTiming(start: 0.0, end: 3.0),
        Fragment(index: 1, text: 'Verse 2', status: FragmentStatus.auto)
          ..setRealTiming(start: 3.0, end: 6.0),
      ];

      appManager.value = appManager.value.copyWith(
        fragments: frags,
        selectedFragmentIndex: 0,
      );

      appManager.markReviewedAndAdvance();

      expect(appManager.value.fragments[0].status, FragmentStatus.reviewed);
      expect(appManager.value.selectedFragmentIndex, 1);

      appManager.dispose();
    });

    test('nudgeActiveBoundary seeks directly to newStart and stays paused when paused', () {
      final appManager = AppManager();
      final frags = [
        Fragment(index: 0, text: 'Verse 1')..setRealTiming(start: 0.0, end: 5.0),
        Fragment(index: 1, text: 'Verse 2')..setRealTiming(start: 5.0, end: 10.0),
      ];

      appManager.value = appManager.value.copyWith(
        fragments: frags,
        audioDuration: const Duration(seconds: 10),
        isPlaying: false,
      );

      // Playhead inside fragment 1 at 7.0s
      appManager.playbackPosition.value = const Duration(seconds: 7);

      appManager.nudgeActiveBoundary(0.150);

      expect(appManager.value.fragments[1].realStart, closeTo(5.150, 0.001));
      // Previous fragment's realEnd adjusted accordingly
      expect(appManager.value.fragments[0].realEnd, closeTo(5.150, 0.001));
      expect(appManager.value.selectedFragmentIndex, 1);
      // Remained paused
      expect(appManager.value.isPlaying, isFalse);

      appManager.dispose();
    });

    test('nudgeActiveBoundary falls back to selectedFragmentIndex when playhead is outside timed fragments', () {
      final appManager = AppManager();
      final frags = [
        Fragment(index: 0, text: 'Verse 1')..setRealTiming(start: 2.0, end: 5.0),
        Fragment(index: 1, text: 'Verse 2')..setRealTiming(start: 5.0, end: 10.0),
      ];

      appManager.value = appManager.value.copyWith(
        fragments: frags,
        audioDuration: const Duration(seconds: 15),
        selectedFragmentIndex: 1,
      );

      // Playhead at 0.5s (before any timed fragment starts)
      appManager.playbackPosition.value = const Duration(milliseconds: 500);

      appManager.nudgeActiveBoundary(0.150);

      // Falls back to selectedFragmentIndex (1)
      expect(appManager.value.fragments[1].realStart, closeTo(5.150, 0.001));

      appManager.dispose();
    });

    test('skipToPrevious skips to start of current fragment if > 300ms in, or previous fragment if <= 300ms in', () {
      final appManager = _TestAppManager();
      final frags = [
        Fragment(index: 0, text: 'Verse 1')..setRealTiming(start: 0.0, end: 3.0),
        Fragment(index: 1, text: 'Verse 2')..setRealTiming(start: 3.0, end: 6.0),
        Fragment(index: 2, text: 'Verse 3')..setRealTiming(start: 6.0, end: 9.0),
      ];

      appManager.value = appManager.value.copyWith(
        fragments: frags,
        selectedFragmentIndex: 1,
      );

      // 1. Playhead inside fragment 1 at 3.5s (3500ms > 3000ms + 300ms)
      appManager.playbackPosition.value = const Duration(milliseconds: 3500);
      appManager.skipToPrevious();
      // Should seek to start of current fragment (fragment 1 at 3000ms)
      expect(appManager.lastSoughtPosition, const Duration(milliseconds: 3000));

      // 2. Playhead at start of fragment 1 (3000ms <= 3000ms + 300ms)
      // (e.g. double press or right after jumping to start)
      appManager.playbackPosition.value = const Duration(milliseconds: 3000);
      appManager.skipToPrevious();
      // Should seek to previous fragment (fragment 0 at 0ms)
      expect(appManager.lastSoughtPosition, const Duration(milliseconds: 0));

      // 3. Playhead at 3200ms into fragment 1 (< 3000ms + 300ms)
      appManager.playbackPosition.value = const Duration(milliseconds: 3200);
      appManager.skipToPrevious();
      // Within 300ms threshold, should seek to previous fragment (fragment 0 at 0ms)
      expect(appManager.lastSoughtPosition, const Duration(milliseconds: 0));

      // 4. Playhead at 3301ms into fragment 1 (> 3000ms + 300ms)
      appManager.playbackPosition.value = const Duration(milliseconds: 3301);
      appManager.skipToPrevious();
      // Beyond 300ms threshold, should seek to start of current fragment (3000ms)
      expect(appManager.lastSoughtPosition, const Duration(milliseconds: 3000));

      appManager.dispose();
    });

    test('playCurrentFragment prioritizes playhead fragment and falls back to selection', () {
      final appManager = _TestAppManager();
      final frags = [
        Fragment(index: 0, text: 'Verse 1')..setRealTiming(start: 0.0, end: 3.0),
        Fragment(index: 1, text: 'Verse 2')..setRealTiming(start: 3.0, end: 6.0),
      ];

      appManager.value = appManager.value.copyWith(
        fragments: frags,
        selectedFragmentIndex: 0,
      );

      // 1. Playhead in fragment 1 at 4.5s -> should play fragment 1 (starts at 3.0s)
      // even though selectedFragmentIndex is 0
      appManager.playbackPosition.value = const Duration(milliseconds: 4500);
      appManager.playCurrentFragment();
      expect(appManager.lastSoughtPosition, const Duration(milliseconds: 3000));
      expect(appManager.playbackPosition.value, const Duration(milliseconds: 3000));

      // 2. Playhead outside timed audio at 10.0s -> falls back to selectedFragmentIndex (0, starts at 0.0s)
      appManager.playbackPosition.value = const Duration(seconds: 10);
      appManager.playCurrentFragment();
      expect(appManager.lastSoughtPosition, const Duration(milliseconds: 0));
      expect(appManager.playbackPosition.value, const Duration(milliseconds: 0));

      appManager.dispose();
    });

    test('playCurrentFragment resets playhead to beginning of fragment on completion', () {
      final appManager = _TestAppManager();
      final frags = [
        Fragment(index: 0, text: 'Verse 1')..setRealTiming(start: 0.0, end: 3.0),
        Fragment(index: 1, text: 'Verse 2')..setRealTiming(start: 3.0, end: 6.0),
      ];

      appManager.value = appManager.value.copyWith(
        fragments: frags,
        selectedFragmentIndex: 0,
      );

      // Play fragment 0 (0.0s to 3.0s)
      appManager.playbackPosition.value = const Duration(milliseconds: 1500);
      appManager.playCurrentFragment();
      expect(appManager.lastSoughtPosition, const Duration(milliseconds: 0));
      expect(appManager.playbackPosition.value, const Duration(milliseconds: 0));

      // Simulate playback reaching end of fragment (3000ms)
      appManager.handleAudioPosition(const Duration(milliseconds: 3000));

      // Playhead should be reset to start of fragment 0 (0ms), not remaining at 3000ms
      expect(appManager.lastSoughtPosition, const Duration(milliseconds: 0));
      expect(appManager.playbackPosition.value, const Duration(milliseconds: 0));

      // Simulate any stale stream position event arriving right after pause/seek
      appManager.handleAudioPosition(const Duration(milliseconds: 3010));
      // Stale event should be discarded, playhead still at 0ms
      expect(appManager.playbackPosition.value, const Duration(milliseconds: 0));

      // Pressing P again now should play the SAME fragment (fragment 0), NOT fragment 1
      appManager.playCurrentFragment();
      expect(appManager.lastSoughtPosition, const Duration(milliseconds: 0));
      expect(appManager.playbackPosition.value, const Duration(milliseconds: 0));

      appManager.dispose();
    });

    testWidgets('nudgeActiveBoundary latches onto active fragment while modifier is held down', (tester) async {
      final appManager = AppManager();
      final frags = [
        Fragment(index: 0, text: 'Verse 1')..setRealTiming(start: 0.0, end: 5.0),
        Fragment(index: 1, text: 'Verse 2')..setRealTiming(start: 5.0, end: 10.0),
        Fragment(index: 2, text: 'Verse 3')..setRealTiming(start: 10.0, end: 15.0),
      ];

      appManager.value = appManager.value.copyWith(
        fragments: frags,
        audioDuration: const Duration(seconds: 15),
      );

      // Press Meta key
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);

      // Playhead in fragment 1
      appManager.playbackPosition.value = const Duration(seconds: 7);

      // First nudge: targets fragment 1
      appManager.nudgeActiveBoundary(0.150);
      expect(appManager.value.fragments[1].realStart, closeTo(5.150, 0.001));
      expect(appManager.value.selectedFragmentIndex, 1);

      // Advance playhead into fragment 2 (12.0s) while Meta is STILL held down
      appManager.playbackPosition.value = const Duration(seconds: 12);

      // Second nudge: should STILL target fragment 1 because Meta is held down
      appManager.nudgeActiveBoundary(0.150);
      expect(appManager.value.fragments[1].realStart, closeTo(5.300, 0.001));
      expect(appManager.value.selectedFragmentIndex, 1);
      // Fragment 2 was not touched
      expect(appManager.value.fragments[2].realStart, 10.0);

      // Now release Meta key
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      appManager.clearNudgeLatch();

      // Third nudge: playhead is at 12.0s (fragment 2), so it now targets fragment 2
      appManager.playbackPosition.value = const Duration(seconds: 12);
      appManager.nudgeActiveBoundary(0.150);
      expect(appManager.value.fragments[2].realStart, closeTo(10.150, 0.001));
      expect(appManager.value.selectedFragmentIndex, 2);

      appManager.dispose();
    });

    test('selectFragment clears the nudge latch', () {
      final appManager = AppManager();
      final frags = [
        Fragment(index: 0, text: 'Verse 1')..setRealTiming(start: 0.0, end: 5.0),
        Fragment(index: 1, text: 'Verse 2')..setRealTiming(start: 5.0, end: 10.0),
      ];

      appManager.value = appManager.value.copyWith(
        fragments: frags,
        audioDuration: const Duration(seconds: 10),
      );

      // Nudge fragment 0
      appManager.playbackPosition.value = const Duration(seconds: 2);
      appManager.nudgeActiveBoundary(0.150);
      expect(appManager.value.fragments[0].realStart, closeTo(0.150, 0.001));

      // Selecting a new fragment resets the latch
      appManager.selectFragment(1);

      // Even if playhead is at 2.0s, fallback or latch won't use previous latch
      appManager.playbackPosition.value = const Duration(seconds: 8); // in fragment 1
      appManager.nudgeActiveBoundary(0.150);
      expect(appManager.value.fragments[1].realStart, closeTo(5.150, 0.001));

      appManager.dispose();
    });

    testWidgets('StudioEditor shortcuts nudge by 150ms, 50ms, and 500ms', (tester) async {
      final appManager = AppManager();
      final frags = [
        Fragment(index: 0, text: 'Verse 1')..setRealTiming(start: 0.0, end: 5.0),
        Fragment(index: 1, text: 'Verse 2')..setRealTiming(start: 5.0, end: 10.0),
      ];

      appManager.value = appManager.value.copyWith(
        fragments: frags,
        audioDuration: const Duration(seconds: 10),
        selectedFragmentIndex: 0,
      );
      appManager.playbackPosition.value = const Duration(seconds: 2); // In Verse 1

      await tester.pumpWidget(
        MacosApp(
          home: MacosWindow(
            child: StudioEditor(homeManager: appManager),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Standard nudge: Cmd + ArrowRight (150ms)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(appManager.value.fragments[0].realStart, closeTo(0.150, 0.001));

      // Fine nudge: Cmd + Alt + ArrowRight (50ms)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(appManager.value.fragments[0].realStart, closeTo(0.200, 0.001));

      // Coarse nudge: Cmd + Shift + ArrowRight (500ms)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(appManager.value.fragments[0].realStart, closeTo(0.700, 0.001));

      appManager.dispose();
    });

    testWidgets('StudioEditor pressing P triggers playCurrentFragment', (tester) async {
      final appManager = _TestAppManager();
      final frags = [
        Fragment(index: 0, text: 'Verse 1')..setRealTiming(start: 0.0, end: 3.0),
      ];
      appManager.value = appManager.value.copyWith(
        fragments: frags,
        selectedFragmentIndex: 0,
      );

      await tester.pumpWidget(
        MacosApp(
          home: MacosWindow(
            child: StudioEditor(homeManager: appManager),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.pump();

      expect(appManager.playCurrentFragmentCalled, isTrue);

      appManager.dispose();
    });

    testWidgets('nudging timing does not recenter waveform when fragment is on-screen', (tester) async {
      final appManager = AppManager();
      final frags = [
        Fragment(index: 0, text: 'Verse 1')..setRealTiming(start: 0.0, end: 10.0),
        Fragment(index: 1, text: 'Verse 2')..setRealTiming(start: 10.0, end: 50.0),
      ];

      appManager.value = appManager.value.copyWith(
        fragments: frags,
        audioDuration: const Duration(seconds: 100),
        zoomLevel: 5.0,
        waveform: createMockWaveform(),
        selectedFragmentIndex: 0,
      );
      // Playhead at 2.0s
      appManager.playbackPosition.value = const Duration(seconds: 2);

      await tester.pumpWidget(
        MacosApp(
          home: MacosWindow(
            child: StudioEditor(homeManager: appManager),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollFinder = find.descendant(
        of: find.byType(WaveformView),
        matching: find.byType(SingleChildScrollView),
      );
      final scrollController =
          tester.widget<SingleChildScrollView>(scrollFinder).controller!;

      // Position view at offset 20.0 so that fragment 0 (absolutePlayhead ~ 46.0) is visible on-screen (20..820)
      scrollController.jumpTo(20.0);
      await tester.pumpAndSettle();
      expect(scrollController.offset, 20.0);

      // Nudge timing of fragment 0 while on-screen
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      // Timing was updated to 0.150s
      expect(appManager.value.fragments[0].realStart, closeTo(0.150, 0.001));
      // View should NOT recenter or move; remains at 20.0 because it was on-screen
      expect(scrollController.offset, 20.0);

      // Now scroll view far away to offset 500.0 (so fragment 0 is off-screen to the left)
      scrollController.jumpTo(500.0);
      await tester.pumpAndSettle();
      expect(scrollController.offset, 500.0);

      // Nudge timing again while off-screen
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      // Timing was updated to 0.300s
      expect(appManager.value.fragments[0].realStart, closeTo(0.300, 0.001));
      // View moves to the beginning of the waveform view (playheadContentPixel = (0.3 / 100) * 4000 = 12.0)
      expect(scrollController.offset, closeTo(12.0, 1.0));

      appManager.dispose();
    });
  });
}
