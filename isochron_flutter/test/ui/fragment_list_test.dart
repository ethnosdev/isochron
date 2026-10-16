import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isochron_cli/isochron_cli.dart';
import 'package:isochron_flutter/ui/waveform/fragment_list.dart';

void main() {
  Widget buildTestWidget({required List<Fragment> fragments}) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: FragmentList(
            fragments: fragments,
            currentPos: Duration.zero,
            onJumpTo: (_) {},
            onDoubleTap: (_) {},
            onSelect: (_) {},
            onCapture: (_) {},
            onClear: (_) {},
          ),
        ),
      ),
    );
  }

  group('FragmentList romanization display', () {
    testWidgets('does not show second line when text is already Latin', (tester) async {
      final fragments = [
        Fragment(index: 0, text: 'In the beginning was the Word'),
        Fragment(index: 1, text: '¡Hola! ¿Cómo estás?'),
      ];

      await tester.pumpWidget(buildTestWidget(fragments: fragments));
      await tester.pumpAndSettle();

      expect(find.text('In the beginning was the Word'), findsOneWidget);
      expect(find.text('¡Hola! ¿Cómo estás?'), findsOneWidget);
    });

    testWidgets('shows second line with non-italic, high-contrast, wrapping romanized text', (tester) async {
      final fragments = [
        Fragment(index: 0, text: 'Βίβλος γενέσεως Ἰησοῦ Χριστοῦ'),
        Fragment(index: 1, text: 'בְּרֵאשִׁית בָּרָא אֱלֹהִים'),
      ];

      await tester.pumpWidget(buildTestWidget(fragments: fragments));
      await tester.pumpAndSettle();

      expect(find.text('Βίβλος γενέσεως Ἰησοῦ Χριστοῦ'), findsOneWidget);
      expect(find.text('בְּרֵאשִׁית בָּרָא אֱלֹהִים'), findsOneWidget);

      expect(find.text('Biblos geneseos Iesou Christou'), findsOneWidget);
      expect(find.text('bereashiyt baraa elohim'), findsOneWidget);

      final romanizedWidget = tester.widget<Text>(find.text('Biblos geneseos Iesou Christou'));
      expect(romanizedWidget.style?.fontSize, 13.5);
      expect(romanizedWidget.style?.fontStyle, isNot(FontStyle.italic));
      final originalWidget = tester.widget<Text>(find.text('Βίβλος γενέσεως Ἰησοῦ Χριστοῦ'));
      // Text color is the same as the original text
      expect(romanizedWidget.style?.color, equals(originalWidget.style?.color));
      expect(romanizedWidget.maxLines, isNull);
      expect(originalWidget.maxLines, isNull);
      expect(originalWidget.overflow, isNot(TextOverflow.ellipsis));

      // Check vertical alignment: original and romanized lines share the exact same X coordinate
      final origPos = tester.getTopLeft(find.text('Βίβλος γενέσεως Ἰησοῦ Χριστοῦ'));
      final romPos = tester.getTopLeft(find.text('Biblos geneseos Iesou Christou'));
      expect(origPos.dx, equals(romPos.dx));
    });

    testWidgets('vertically aligns original and romanized text when ID is present', (tester) async {
      final fragments = [
        Fragment(
          index: 0,
          id: 'MAT.1.1',
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
