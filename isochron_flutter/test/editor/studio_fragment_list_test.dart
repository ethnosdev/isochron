import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isochron_cli/isochron_cli.dart';
import 'package:isochron_flutter/ui/editor/components/studio_fragment_list.dart';
import 'package:macos_ui/macos_ui.dart';

void main() {
  Widget buildTestWidget({
    required List<Fragment> fragments,
    ValueNotifier<Duration>? playbackNotifier,
  }) {
    return MacosApp(
      home: MacosWindow(
        child: SizedBox(
          width: 800,
          height: 600,
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
      final originalWidget = tester.widget<Text>(find.text('Βίβλος γενέσεως Ἰησοῦ Χριστοῦ'));
      // Text color is the same as the original text
      expect(romanizedWidget.style?.color, equals(originalWidget.style?.color));
      // No maxLines or ellipsis (lines wrap)
      expect(romanizedWidget.maxLines, isNull);
      expect(romanizedWidget.overflow, isNot(TextOverflow.ellipsis));
      expect(originalWidget.maxLines, isNull);
      expect(originalWidget.overflow, isNot(TextOverflow.ellipsis));

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

      final idPos = tester.getTopLeft(find.text('MAT.1.1'));
      expect(origPos.dx, greaterThan(idPos.dx));
    });
  });
}
