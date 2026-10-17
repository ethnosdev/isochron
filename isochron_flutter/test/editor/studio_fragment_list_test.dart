import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isochron_cli/isochron_cli.dart';
import 'package:isochron_flutter/ui/editor/components/studio_fragment_list.dart';
import 'package:isochron_flutter/ui/theme/app_theme.dart';
import 'package:macos_ui/macos_ui.dart';

void main() {
  Widget buildTestWidget({
    required List<Fragment> fragments,
    ValueNotifier<Duration>? playbackNotifier,
    double height = 600,
  }) {
    return MacosApp(
      home: MacosWindow(
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 800,
            height: height,
            child: StudioFragmentList(
              fragments: fragments,
              playbackNotifier: playbackNotifier ?? ValueNotifier(Duration.zero),
              onSelect: (_) {},
              onJumpTo: (_) {},
              onDoubleTap: (_) {},
              onCapture: (_) {},
              onClear: (_) {},
            ),
          ),
        ),
      ),
    );
  }

  group('StudioFragmentList romanization display', () {
    testWidgets('does not show second line when text is already Latin', (tester) async {
      final fragments = [
        Fragment(index: 0, text: 'In the beginning was the Word'),
        Fragment(index: 1, text: '¡Hola! ¿Cómo estás?'),
      ];

      await tester.pumpWidget(buildTestWidget(fragments: fragments));
      await tester.pumpAndSettle();

      expect(find.text('In the beginning was the Word'), findsOneWidget);
      expect(find.text('¡Hola! ¿Cómo estás?'), findsOneWidget);

      // Verify no romanized second line exists
      expect(find.text('In the beginning was the Word'), findsOneWidget);
      final textWidgets = tester.widgetList<Text>(find.byType(Text));
      expect(textWidgets.any((t) => t.data == 'In the beginning was the Word' && t.maxLines == 1), isFalse);
    });

    testWidgets('shows second line with non-italic, high-contrast, wrapping romanized text', (tester) async {
      final fragments = [
        Fragment(index: 0, text: 'Βίβλος γενέσεως Ἰησοῦ Χριστοῦ'),
        Fragment(index: 1, text: 'בְּרֵאשִׁית בָּרָא אֱלֹהִים'),
      ];

      await tester.pumpWidget(buildTestWidget(fragments: fragments));
      await tester.pumpAndSettle();

      // Original text is rendered
      expect(find.text('Βίβλος γενέσεως Ἰησοῦ Χριστοῦ'), findsOneWidget);
      expect(find.text('בְּרֵאשִׁית בָּרָא אֱלֹהִים'), findsOneWidget);

      // Romanized text is rendered on second line
      expect(find.text('Biblos geneseos Iesou Christou'), findsOneWidget);
      expect(find.text('bereashiyt baraa elohim'), findsOneWidget);

      final romanizedWidget = tester.widget<Text>(find.text('Biblos geneseos Iesou Christou'));
      // Font size is 13.0 (same size as original, not smaller)
      expect(romanizedWidget.style?.fontSize, 13.0);
      // Not italic (easier to read)
      expect(romanizedWidget.style?.fontStyle, isNot(FontStyle.italic));
      // Weight is w500 (distinct and easy to see, not a faint/light font)
      expect(romanizedWidget.style?.fontWeight, FontWeight.w500);
      // Text color uses AppTheme.lightRomanized
      expect(romanizedWidget.style?.color, equals(AppTheme.lightRomanized));
      // No maxLines or ellipsis (lines wrap)
      expect(romanizedWidget.maxLines, isNull);
      expect(romanizedWidget.overflow, isNot(TextOverflow.ellipsis));

      // Check vertical alignment: original and romanized lines share the exact same X coordinate
      final origPos = tester.getTopLeft(find.text('Βίβλος γενέσεως Ἰησοῦ Χριστοῦ'));
      final romPos = tester.getTopLeft(find.text('Biblos geneseos Iesou Christou'));
      expect(origPos.dx, equals(romPos.dx));
    });

    testWidgets('vertically aligns original and romanized text when ID and badges are present', (tester) async {
      final fragments = [
        Fragment(
          index: 0,
          id: 'MAT.1.1',
          status: FragmentStatus.auto,
          text: 'Βίβλος γενέσεως Ἰησοῦ Χριστοῦ',
        ),
      ];

      await tester.pumpWidget(buildTestWidget(fragments: fragments));
      await tester.pumpAndSettle();

      final origPos = tester.getTopLeft(find.text('Βίβλος γενέσεως Ἰησοῦ Χριστοῦ'));
      final romPos = tester.getTopLeft(find.text('Biblos geneseos Iesou Christou'));
      expect(origPos.dx, equals(romPos.dx));

      // ID and badges are on Sub-row A, above original text on Sub-row B
      final idPos = tester.getTopLeft(find.text('MAT.1.1'));
      expect(origPos.dy, greaterThan(idPos.dy));
    });
  });

  group('StudioFragmentList scrolling near end of list', () {
    testWidgets('does not scroll current item up when last item is visible in the viewport', (tester) async {
      final playbackNotifier = ValueNotifier<Duration>(Duration.zero);
      final fragments = List.generate(
        5,
        (i) => Fragment(
          index: i,
          text: 'Fragment verse $i',
        )..setRealTiming(start: i * 2.0, end: (i + 1) * 2.0),
      );

      await tester.pumpWidget(
        buildTestWidget(
          fragments: fragments,
          playbackNotifier: playbackNotifier,
        ),
      );
      await tester.pumpAndSettle();

      // All 5 items fit in 600px viewport, so the last item (Fragment verse 4) is visible
      expect(find.text('Fragment verse 4'), findsOneWidget);
      final initialVerse3Pos = tester.getTopLeft(find.text('Fragment verse 3'));

      // Advance playback to Fragment verse 3 (starts at 6.0s)
      playbackNotifier.value = const Duration(milliseconds: 6500);
      await tester.pumpAndSettle();

      // Because the last item is visible and verse 3 is already visible,
      // it should not attempt to scroll verse 3 up to the top
      final currentVerse3Pos = tester.getTopLeft(find.text('Fragment verse 3'));
      expect(currentVerse3Pos.dy, equals(initialVerse3Pos.dy));

      playbackNotifier.dispose();
    });

    testWidgets('scrolls current item up when last item is NOT visible', (tester) async {
      final playbackNotifier = ValueNotifier<Duration>(Duration.zero);
      final fragments = List.generate(
        50,
        (i) => Fragment(
          index: i,
          text: 'Fragment verse $i',
        )..setRealTiming(start: i * 2.0, end: (i + 1) * 2.0),
      );

      await tester.pumpWidget(
        buildTestWidget(
          fragments: fragments,
          playbackNotifier: playbackNotifier,
        ),
      );
      await tester.pumpAndSettle();

      // In a long list of 50 items, last item (Fragment verse 49) is NOT visible
      expect(find.text('Fragment verse 49'), findsNothing);
      final initialVerse5Pos = tester.getTopLeft(find.text('Fragment verse 5'));

      // Advance playback to Fragment verse 5 (starts at 10.0s)
      playbackNotifier.value = const Duration(milliseconds: 10500);
      await tester.pumpAndSettle();

      // Since last item is NOT visible, verse 5 scrolls up towards target alignment
      final currentVerse5Pos = tester.getTopLeft(find.text('Fragment verse 5'));
      expect(currentVerse5Pos.dy, lessThan(initialVerse5Pos.dy));

      playbackNotifier.dispose();
    });

    testWidgets('scrolls enough to reveal the full last item if it is not showing fully', (tester) async {
      final playbackNotifier = ValueNotifier<Duration>(Duration.zero);
      // Create 3 items in a 130px height viewport so that item 2 (last item) is partially cut off at the bottom
      final fragments = List.generate(
        3,
        (i) => Fragment(
          index: i,
          text: 'Fragment verse $i',
        )..setRealTiming(start: i * 2.0, end: (i + 1) * 2.0),
      );

      await tester.pumpWidget(
        buildTestWidget(
          fragments: fragments,
          playbackNotifier: playbackNotifier,
          height: 130,
        ),
      );
      await tester.pumpAndSettle();

      // Verify last item is visible but partially cut off at bottom
      final lastItemFinder = find.text('Fragment verse 2');
      expect(lastItemFinder, findsOneWidget);
      final initialLastItemBottom = tester.getBottomLeft(lastItemFinder).dy;
      expect(initialLastItemBottom, greaterThan(130.0));

      // Advance playback to Fragment verse 1 (starts at 2.0s)
      playbackNotifier.value = const Duration(milliseconds: 2500);
      await tester.pumpAndSettle();

      // The list should scroll just enough to reveal the full last item within the 130px viewport
      final currentLastItemBottom = tester.getBottomLeft(lastItemFinder).dy;
      expect(currentLastItemBottom, lessThan(initialLastItemBottom));
      expect(currentLastItemBottom, lessThanOrEqualTo(130.0 + 1.0));

      // Advance playback again to Fragment verse 2 (starts at 4.0s)
      playbackNotifier.value = const Duration(milliseconds: 4500);
      await tester.pumpAndSettle();

      // Since the full last item is now visible, it does not scroll again
      final subsequentLastItemBottom = tester.getBottomLeft(lastItemFinder).dy;
      expect(subsequentLastItemBottom, equals(currentLastItemBottom));

      playbackNotifier.dispose();
    });
  });
}
