import 'package:isochron_cli/src/mms/mms_tokenizer.dart';
import 'package:test/test.dart';

void main() {
  group('MmsTokenizer', () {
    late MmsTokenizer tokenizer;

    setUp(() {
      tokenizer = MmsTokenizer();
    });

    test('normalizes English text', () {
      final res = tokenizer.normalizeText('In the beginning, God created!');
      expect(res.normalized, equals('in the beginning god created'));
      expect(res.warnings, isEmpty);
    });

    test('drops digits and reports warning', () {
      final res = tokenizer.normalizeText('Verse 14: let there be light.');
      expect(res.normalized, equals('verse let there be light'));
      expect(res.warnings.any((w) => w.contains('Digits dropped')), isTrue);
    });

    test('romanizes Greek script with diacritics', () {
      final res = tokenizer.normalizeText('¶Βίβλος γενέσεως ˚Ἰησοῦ', languageCode: 'ell');
      expect(res.normalized, contains('vivlos'));
      expect(res.warnings, isEmpty);
    });

    test('romanizes Hebrew script', () {
      final res = tokenizer.normalizeText('וְאֵלֶּה שְׁמוֹת', languageCode: 'heb');
      expect(res.normalized, isNotEmpty);
      expect(res.warnings, isEmpty);
    });

    test('tokenizes verses with segment star placement', () {
      final verses = ['First verse', 'Second verse'];
      final output = tokenizer.tokenizeVerses(
        verses,
        starPlacement: StarPlacement.segment,
      );

      // Should be: [*] + verse0 + [*] + verse1 + [*]
      expect(output.tokenChars.first, equals('*'));
      expect(output.tokenChars.last, equals('*'));
      expect(output.verseRanges.length, equals(2));

      // Check verse 0 bounds
      final v0 = output.verseRanges[0];
      expect(v0.tokenStartIndex, equals(1)); // after initial star
      expect(output.tokenChars[v0.tokenEndIndex], equals('*')); // trailing star after v0

      // Check verse 1 bounds
      final v1 = output.verseRanges[1];
      expect(v1.tokenStartIndex, equals(v0.tokenEndIndex + 1));
      expect(output.tokenChars[v1.tokenEndIndex], equals('*'));
    });

    test('tokenizes verses with edges star placement', () {
      final verses = ['First verse', 'Second verse'];
      final output = tokenizer.tokenizeVerses(
        verses,
        starPlacement: StarPlacement.edges,
      );

      expect(output.tokenChars.first, equals('*'));
      expect(output.tokenChars.last, equals('*'));
      expect(output.verseRanges.length, equals(2));

      final v0 = output.verseRanges[0];
      final v1 = output.verseRanges[1];
      expect(v0.tokenEndIndex, equals(v1.tokenStartIndex)); // adjacent without star in between
    });
  });
}
