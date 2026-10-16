import 'package:test/test.dart';
import 'package:isochron_cli/isochron_cli.dart';

void main() {
  group('Romanizer', () {
    test('isAlreadyRomanized returns true for Latin scripts', () {
      expect(Romanizer.isAlreadyRomanized(''), isTrue);
      expect(Romanizer.isAlreadyRomanized('   '), isTrue);
      expect(Romanizer.isAlreadyRomanized('12345! .,'), isTrue);
      expect(Romanizer.isAlreadyRomanized('Hello world'), isTrue);
      expect(Romanizer.isAlreadyRomanized('In the beginning was the Word'), isTrue);
      expect(Romanizer.isAlreadyRomanized('¡Hola! ¿Cómo estás? El niño está aquí.'), isTrue);
      expect(Romanizer.isAlreadyRomanized("C'est l'été à Paris."), isTrue);
      expect(Romanizer.isAlreadyRomanized('Grüße über den Fluss.'), isTrue);
      expect(Romanizer.isAlreadyRomanized('Tiếng Việt là ngôn ngữ.'), isTrue);
      expect(Romanizer.isAlreadyRomanized('Zażółć gęślą jaźń.'), isTrue);
      expect(Romanizer.isAlreadyRomanized('İstanbul Boğazı.'), isTrue);
    });

    test('isAlreadyRomanized returns false for non-Latin scripts', () {
      expect(Romanizer.isAlreadyRomanized('Βίβλος γενέσεως'), isFalse);
      expect(Romanizer.isAlreadyRomanized('בְּרֵאשִׁית בָּרָא אֱלֹהִים'), isFalse);
      expect(Romanizer.isAlreadyRomanized('В начале было Слово'), isFalse);
      expect(Romanizer.isAlreadyRomanized('في البدء كان الكلمة'), isFalse);
      expect(Romanizer.isAlreadyRomanized('起初神创造天地'), isFalse);
      expect(Romanizer.isAlreadyRomanized('초기에'), isFalse);
      expect(Romanizer.isAlreadyRomanized('はじめに'), isFalse);
      expect(Romanizer.isAlreadyRomanized('በመጀመሪያ'), isFalse);
      expect(Romanizer.isAlreadyRomanized('Chapter 1: Βίβλος'), isFalse);
    });

    test('romanize returns null for Latin text', () {
      expect(Romanizer.romanize('Hello world'), isNull);
      expect(Romanizer.romanize('¡Hola! ¿Cómo estás?'), isNull);
      expect(Romanizer.romanize('12345'), isNull);
      expect(Romanizer.romanize(''), isNull);
    });

    test('romanize produces romanized text for non-Latin scripts', () {
      expect(
        Romanizer.romanize('Βίβλος γενέσεως'),
        'Biblos geneseos',
      );
      expect(
        Romanizer.romanize('בְּרֵאשִׁית בָּרָא אֱלֹהִים'),
        'bereashiyt baraa elohim',
      );
      expect(
        Romanizer.romanize('В начале было Слово'),
        'V nachale bylo Slovo',
      );
      expect(
        Romanizer.romanize('Verse 1: Βίβλος'),
        'Verse 1: Biblos',
      );
    });

    test('romanize respects optional languageCode', () {
      final greekWithEll = Romanizer.romanize('Βίβλος', languageCode: 'ell');
      expect(greekWithEll, 'Vivlos');
    });
  });

  group('Fragment.romanizedText integration', () {
    test('returns null for Latin fragment text', () {
      final frag = Fragment(index: 0, text: 'In the beginning');
      expect(frag.romanizedText, isNull);
    });

    test('returns romanized string for non-Latin fragment text and caches it', () {
      final frag = Fragment(index: 0, text: 'Βίβλος γενέσεως');
      expect(frag.romanizedText, 'Biblos geneseos');
      // Repeated access uses cached value
      expect(frag.romanizedText, 'Biblos geneseos');
    });

    test('copyWith preserves cached romanization when text does not change', () {
      final frag = Fragment(index: 0, text: 'Βίβλος γενέσεως');
      expect(frag.romanizedText, 'Biblos geneseos');

      final updated = frag.copyWith(autoStart: 1.5);
      expect(updated.romanizedText, 'Biblos geneseos');
    });

    test('copyWith resets romanization when text changes', () {
      final frag = Fragment(index: 0, text: 'Βίβλος');
      expect(frag.romanizedText, 'Biblos');

      final updated = frag.copyWith(text: 'Hello world');
      expect(updated.romanizedText, isNull);

      final updatedGreek = frag.copyWith(text: 'γενέσεως');
      expect(updatedGreek.romanizedText, 'geneseos');
    });

    test('serializes to JSON and deserializes correctly', () {
      final greekFrag = Fragment(
        index: 1,
        id: '40001001',
        text: 'Βίβλος γενέσεως',
      );
      final json = greekFrag.toJson();
      expect(json['romanizedText'], 'Biblos geneseos');

      final reconstructed = Fragment.fromJson(json);
      expect(reconstructed.romanizedText, 'Biblos geneseos');
    });
  });
}
