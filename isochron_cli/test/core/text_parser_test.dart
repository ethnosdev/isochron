import 'package:isochron_cli/isochron_cli.dart';
import 'package:test/test.dart';

void main() {
  group('splitIdAndText', () {
    test('splits tab-delimited verse-letter IDs', () {
      final samples = {
        's1\tlaa nethantogto be go pezi kor.': (
          id: 's1',
          text: 'laa nethantogto be go pezi kor.',
        ),
        '1a\tkon chhog gi ku dunlu nge': (
          id: '1a',
          text: 'kon chhog gi ku dunlu nge',
        ),
        '1b\tmi sonpo nge shi song mi tshu lu': (
          id: '1b',
          text: 'mi sonpo nge shi song mi tshu lu',
        ),
        'is1\tIntroduction Section 1': (
          id: 'is1',
          text: 'Introduction Section 1',
        ),
        '4-5a\tCombined verses phrase': (
          id: '4-5a',
          text: 'Combined verses phrase',
        ),
      };

      for (final entry in samples.entries) {
        final result = splitIdAndText(entry.key);
        expect(result.id, entry.value.id);
        expect(result.text, entry.value.text);
      }
    });

    test('splits space-delimited IDs', () {
      final result = splitIdAndText('40001001 In the beginning');
      expect(result.id, '40001001');
      expect(result.text, 'In the beginning');

      final verseResult = splitIdAndText('1:1 In the beginning');
      expect(verseResult.id, '1:1');
      expect(verseResult.text, 'In the beginning');

      final dotResult = splitIdAndText('MAT.1.1 In the beginning');
      expect(dotResult.id, 'MAT.1.1');
      expect(dotResult.text, 'In the beginning');
    });

    test('does not treat natural language words as space-delimited IDs', () {
      final r1 = splitIdAndText('In the beginning was the Word');
      expect(r1.id, isNull);
      expect(r1.text, 'In the beginning was the Word');

      final r2 = splitIdAndText('The book of the generation');
      expect(r2.id, isNull);
      expect(r2.text, 'The book of the generation');

      final r3 = splitIdAndText('Abraham begat Isaac');
      expect(r3.id, isNull);
      expect(r3.text, 'Abraham begat Isaac');
    });

    test('returns null id for single token lines', () {
      final result = splitIdAndText('InTheBeginning');
      expect(result.id, isNull);
      expect(result.text, 'InTheBeginning');
    });

    test('handles empty and whitespace-only lines', () {
      final emptyResult = splitIdAndText('');
      expect(emptyResult.id, isNull);
      expect(emptyResult.text, '');

      final wsResult = splitIdAndText('   \t  ');
      expect(wsResult.id, isNull);
      expect(wsResult.text, '');
    });
  });

  group('detectEmbeddedIds', () {
    test('returns true for tab-delimited text', () {
      const text = 's1\tPhrase text here\ns2\tSecond phrase';
      expect(detectEmbeddedIds(text), isTrue);
    });

    test('returns true for consistent space-delimited ID text', () {
      const text = '''
40001001 The book of generation
40001002 Abraham begat Isaac
40001003 Judas begat Phares
''';
      expect(detectEmbeddedIds(text), isTrue);
    });

    test('returns false for plain natural language text', () {
      const text = '''
The book of the generation of Jesus Christ.
Abraham begat Isaac; and Isaac begat Jacob.
And Judas begat Phares and Zara of Thamar.
''';
      expect(detectEmbeddedIds(text), isFalse);
    });

    test('returns false when only an isolated line starts with a number', () {
      const text = '''
Once upon a time.
3 days later they departed.
And they arrived safely.
Everyone was glad.
''';
      expect(detectEmbeddedIds(text), isFalse);
    });
  });

  group('TextParser.parse with hasIds', () {
    test('extracts IDs and clean text when hasIds is true', () {
      const rawText = '''
s1\tlaa nethantogto be go pezi kor.
1a\tkon chhog gi ku dunlu nge
1b\tmi sonpo nge shi song mi tshu lu
is1\tIntroductory note
4-5a\tCombined verse text
''';
      final fragments = TextParser.parse(rawText, hasIds: true);

      expect(fragments.length, 5);
      expect(fragments[0].id, 's1');
      expect(fragments[0].text, 'laa nethantogto be go pezi kor.');
      expect(fragments[1].id, '1a');
      expect(fragments[1].text, 'kon chhog gi ku dunlu nge');
      expect(fragments[2].id, '1b');
      expect(fragments[2].text, 'mi sonpo nge shi song mi tshu lu');
      expect(fragments[3].id, 'is1');
      expect(fragments[3].text, 'Introductory note');
      expect(fragments[4].id, '4-5a');
      expect(fragments[4].text, 'Combined verse text');
    });

    test('preserves entire line as text and keeps id null when hasIds is false', () {
      const rawText = '''
s1\tlaa nethantogto be go pezi kor.
1a\tkon chhog gi ku dunlu nge
''';
      final fragments = TextParser.parse(rawText, hasIds: false);

      expect(fragments.length, 2);
      expect(fragments[0].id, isNull);
      expect(fragments[0].text, 's1\tlaa nethantogto be go pezi kor.');
      expect(fragments[1].id, isNull);
      expect(fragments[1].text, '1a\tkon chhog gi ku dunlu nge');
    });
  });
}
