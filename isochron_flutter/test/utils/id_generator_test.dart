import 'package:flutter_test/flutter_test.dart';
import 'package:isochron_flutter/utils/id_generator.dart';

void main() {
  group('IdGenerator', () {
    test('extractBookAndChapter detects book and chapter from standard filenames', () {
      final bsb = IdGenerator.extractBookAndChapter('BSB_40_Mat_001');
      expect(bsb.bookNumber, equals(40));
      expect(bsb.chapterNumber, equals(1));
      expect(bsb.bookAbbreviation, equals('MAT'));

      final gen = IdGenerator.extractBookAndChapter('01_Gen_028');
      expect(gen.bookNumber, equals(1));
      expect(gen.chapterNumber, equals(28));

      final nonBible = IdGenerator.extractBookAndChapter('podcast_episode_05');
      expect(nonBible.bookNumber, isNull);
      expect(nonBible.chapterNumber, equals(5));
    });

    test('detectDefaultStyle selects USFM 8-digit for scripture and trackScoped for general audio', () {
      expect(
        IdGenerator.detectDefaultStyle('BSB_40_Mat_001'),
        equals(IdGenerationStyle.usfm8Digit),
      );
      expect(
        IdGenerator.detectDefaultStyle('general_audio_story'),
        equals(IdGenerationStyle.trackScoped),
      );
    });

    test('generateId produces valid USFM 8-digit IDs', () {
      final id0 = IdGenerator.generateId(
        style: IdGenerationStyle.usfm8Digit,
        trackName: 'BSB_40_Mat_001',
        lineIndex: 0,
      );
      expect(id0, equals('40001001'));

      final id1 = IdGenerator.generateId(
        style: IdGenerationStyle.usfm8Digit,
        trackName: 'BSB_40_Mat_001',
        lineIndex: 1,
      );
      expect(id1, equals('40001002'));

      final idCh2 = IdGenerator.generateId(
        style: IdGenerationStyle.usfm8Digit,
        trackName: 'BSB_40_Mat_002',
        lineIndex: 0,
      );
      expect(idCh2, equals('40002001'));
    });

    test('generateId produces valid Track-Scoped IDs', () {
      final id0 = IdGenerator.generateId(
        style: IdGenerationStyle.trackScoped,
        trackName: 'MyLesson',
        lineIndex: 0,
      );
      expect(id0, equals('MyLesson_001'));

      final id1 = IdGenerator.generateId(
        style: IdGenerationStyle.trackScoped,
        trackName: 'MyLesson',
        lineIndex: 1,
      );
      expect(id1, equals('MyLesson_002'));
    });

    test('generatePreview produces preview list', () {
      final preview = IdGenerator.generatePreview(
        style: IdGenerationStyle.usfm8Digit,
        trackName: 'BSB_40_Mat_001',
        count: 3,
      );
      expect(preview, equals(['40001001', '40001002', '40001003']));
    });
  });
}
