import 'package:test/test.dart';
import 'package:isochron_cli/isochron_cli.dart';

void main() {
  group('Fragment Data Structure', () {
    test('should hold basic text and id', () {
      final frag = Fragment(index: 1, text: 'Hello world');
      expect(frag.index, 1);
      expect(frag.text, 'Hello world');
      // Timestamps should default to 0 or null until calculated
      expect(frag.anchorStart, 0.0);
    });

    test('should update real timestamps', () {
      final frag = Fragment(index: 1, text: 'Test');
      frag.setRealTiming(start: 1.5, end: 3.0);
      expect(frag.realStart, 1.5);
      expect(frag.realEnd, 3.0);
    });
  });

  group('Text Parser', () {
    test('should split text by newlines', () {
      final rawText = "Line one.\nLine two.\nLine three.";
      final fragments = TextParser.parse(rawText);

      expect(fragments.length, 3);
      expect(fragments[0].text, "Line one.");
      expect(fragments[0].index, 0); // 0-based index usually easier for lists
      expect(fragments[1].text, "Line two.");
    });

    test('should ignore empty lines', () {
      final rawText = "Line one.\n\n\nLine two.";
      final fragments = TextParser.parse(rawText);
      expect(fragments.length, 2);
    });
  });
}
