import 'package:flutter_test/flutter_test.dart';
import 'package:isochron_flutter/utils/media_pairing_engine.dart';

void main() {
  group('MediaPairingEngine', () {
    test('extractNumbers extracts numbers correctly from paths', () {
      expect(
        MediaPairingEngine.extractNumbers('/path/to/BSB_40_Mat_001.mp3'),
        equals([40, 1]),
      );
      expect(
        MediaPairingEngine.extractNumbers('chapter_05.txt'),
        equals([5]),
      );
      expect(
        MediaPairingEngine.extractNumbers('prologue.mp3'),
        isEmpty,
      );
    });

    test('exactStem strategy pairs identical stems', () {
      final audio = ['BSB_40_Mat_001.mp3', 'BSB_40_Mat_002.mp3', 'audio_extra.mp3'];
      final text = ['BSB_40_Mat_001.txt', 'BSB_40_Mat_002.txt', 'text_extra.txt'];

      final rows = MediaPairingEngine.computePairings(
        audioFiles: audio,
        textFiles: text,
        strategy: PairingStrategy.exactStem,
      );

      expect(rows.length, equals(4));
      // First 2 are paired
      expect(rows[0].audioPath, contains('BSB_40_Mat_001'));
      expect(rows[0].textPath, contains('BSB_40_Mat_001'));
      expect(rows[0].isComplete, isTrue);

      expect(rows[1].audioPath, contains('BSB_40_Mat_002'));
      expect(rows[1].textPath, contains('BSB_40_Mat_002'));
      expect(rows[1].isComplete, isTrue);

      // Remaining are split
      final extraAudio = rows.firstWhere((r) => r.audioPath?.contains('audio_extra') == true);
      expect(extraAudio.textPath, isNull);

      final extraText = rows.firstWhere((r) => r.textPath?.contains('text_extra') == true);
      expect(extraText.audioPath, isNull);
    });

    test('numericTokens strategy pairs files with matching numbers despite different naming', () {
      final audio = [
        'audio_track_01.mp3',
        'audio_track_02.mp3',
        'audio_track_03.mp3',
      ];
      final text = [
        'chapter_01_script.txt',
        'chapter_02_script.txt',
        'chapter_03_script.txt',
      ];

      final rows = MediaPairingEngine.computePairings(
        audioFiles: audio,
        textFiles: text,
        strategy: PairingStrategy.numericTokens,
      );

      expect(rows.length, equals(3));
      for (int i = 0; i < 3; i++) {
        expect(rows[i].isComplete, isTrue);
        expect(rows[i].audioPath, contains('audio_track_0${i + 1}'));
        expect(rows[i].textPath, contains('chapter_0${i + 1}'));
      }
    });

    test('listOrder strategy pairs 1-to-1 in natural sorted order', () {
      final audio = ['apple.mp3', 'banana.mp3', 'cherry.mp3'];
      final text = ['doc1.txt', 'doc2.txt', 'doc3.txt'];

      final rows = MediaPairingEngine.computePairings(
        audioFiles: audio,
        textFiles: text,
        strategy: PairingStrategy.listOrder,
      );

      expect(rows.length, equals(3));
      expect(rows[0].audioPath, equals('apple.mp3'));
      expect(rows[0].textPath, equals('doc1.txt'));

      expect(rows[1].audioPath, equals('banana.mp3'));
      expect(rows[1].textPath, equals('doc2.txt'));

      expect(rows[2].audioPath, equals('cherry.mp3'));
      expect(rows[2].textPath, equals('doc3.txt'));
    });

    test('smartAuto combines stem match, numeric match, and natural sort', () {
      final audio = [
        'BSB_01_identical.mp3',
        'audio_track_10.mp3',
        'intro.mp3',
      ];
      final text = [
        'BSB_01_identical.txt',
        'text_script_10.txt',
        'summary.txt',
      ];

      final rows = MediaPairingEngine.computePairings(
        audioFiles: audio,
        textFiles: text,
        strategy: PairingStrategy.smartAuto,
      );

      expect(rows.length, equals(3));

      // 1. Identical stem
      final identicalRow = rows.firstWhere((r) => r.name.contains('identical'));
      expect(identicalRow.isComplete, isTrue);

      // 2. Numeric match (10)
      final numRow = rows.firstWhere((r) => r.audioPath?.contains('10') == true);
      expect(numRow.textPath, contains('10'));

      // 3. Fallback list order for remainder (intro vs summary)
      final introRow = rows.firstWhere((r) => r.audioPath?.contains('intro') == true);
      expect(introRow.textPath, contains('summary'));
    });

    test('insertGap in text shifts subsequent text down', () {
      final rows = [
        PairedRow(audioPath: 'a1.mp3', textPath: 't1.txt', name: 'Row 1'),
        PairedRow(audioPath: 'a2.mp3', textPath: 't2.txt', name: 'Row 2'),
        PairedRow(audioPath: 'a3.mp3', textPath: 't3.txt', name: 'Row 3'),
      ];

      // Missing t2, insert gap at row index 1
      MediaPairingEngine.insertGap(rows, 1, isText: true);

      expect(rows.length, equals(4));
      expect(rows[0].audioPath, equals('a1.mp3'));
      expect(rows[0].textPath, equals('t1.txt'));

      // Row 1 text is now null, t2 shifted to Row 2
      expect(rows[1].audioPath, equals('a2.mp3'));
      expect(rows[1].textPath, isNull);

      expect(rows[2].audioPath, equals('a3.mp3'));
      expect(rows[2].textPath, equals('t2.txt'));

      // Row 3 text is t3
      expect(rows[3].audioPath, isNull);
      expect(rows[3].textPath, equals('t3.txt'));
    });

    test('shiftUp and shiftDown move items between adjacent rows', () {
      final rows = [
        PairedRow(audioPath: 'a1.mp3', textPath: 't1.txt', name: 'Row 1'),
        PairedRow(audioPath: 'a2.mp3', textPath: 't2.txt', name: 'Row 2'),
      ];

      MediaPairingEngine.shiftDown(rows, 0, isText: true);
      expect(rows[0].textPath, equals('t2.txt'));
      expect(rows[1].textPath, equals('t1.txt'));

      MediaPairingEngine.shiftUp(rows, 1, isText: true);
      expect(rows[0].textPath, equals('t1.txt'));
      expect(rows[1].textPath, equals('t2.txt'));
    });

    test('TrackNameRule updates track names based on audio or text stem', () {
      final rows = [
        PairedRow(
          audioPath: 'audio_file.mp3',
          textPath: 'text_file.txt',
          name: 'initial',
        ),
      ];

      MediaPairingEngine.applyNamingRule(rows, TrackNameRule.audioStem);
      expect(rows[0].name, equals('audio_file'));

      MediaPairingEngine.applyNamingRule(rows, TrackNameRule.textStem);
      expect(rows[0].name, equals('text_file'));
    });
  });
}
