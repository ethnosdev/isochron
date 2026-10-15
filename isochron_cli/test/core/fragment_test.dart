import 'package:test/test.dart';
import 'package:isochron_cli/isochron_cli.dart';

void main() {
  group('Fragment Data Structure', () {
    test('should hold basic text and id', () {
      final frag = Fragment(index: 1, text: 'Hello world');
      expect(frag.index, 1);
      expect(frag.text, 'Hello world');
      expect(frag.realStart, 0.0);
      expect(frag.status, FragmentStatus.auto);
    });

    test('should update real timestamps', () {
      final frag = Fragment(index: 1, text: 'Test');
      frag.setRealTiming(start: 1.5, end: 3.0);
      expect(frag.realStart, 1.5);
      expect(frag.realEnd, 3.0);
    });

    test('should serialize to and from JSON', () {
      final frag = Fragment(
        index: 0,
        id: '40001001',
        text: 'In the beginning',
        autoStart: 1.234,
        confidence: 0.98,
        flags: ['flag1'],
        status: FragmentStatus.edited,
        warnings: ['warn1'],
      )..setRealTiming(start: 1.25, end: 4.5);

      final json = frag.toJson();
      expect(json['id'], '40001001');
      expect(json['start'], 1.25);
      expect(json['end'], 4.5);
      expect(json['autoStart'], 1.234);
      expect(json['status'], 'edited');

      final reconstructed = Fragment.fromJson(json);
      expect(reconstructed.id, frag.id);
      expect(reconstructed.realStart, frag.realStart);
      expect(reconstructed.realEnd, frag.realEnd);
      expect(reconstructed.autoStart, frag.autoStart);
      expect(reconstructed.status, FragmentStatus.edited);
      expect(reconstructed.flags, ['flag1']);
      expect(reconstructed.warnings, ['warn1']);
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
