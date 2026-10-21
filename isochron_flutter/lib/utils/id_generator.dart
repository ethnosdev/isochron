import 'package:path/path.dart' as p;

enum IdGenerationStyle {
  usfm8Digit,
  trackScoped,
}

extension IdGenerationStyleExtension on IdGenerationStyle {
  String get displayName {
    switch (this) {
      case IdGenerationStyle.usfm8Digit:
        return 'USFM 8-Digit (Scripture: 40001001)';
      case IdGenerationStyle.trackScoped:
        return 'Track Name + Number (Track_001)';
    }
  }
}

class IdGenerator {
  static const Map<String, int> bibleBookNumbers = {
    'gen': 1, 'exo': 2, 'lev': 3, 'num': 4, 'deu': 5,
    'jos': 6, 'jdg': 7, 'rut': 8, '1sa': 9, '2sa': 10,
    '1ki': 11, '2ki': 12, '1ch': 13, '2ch': 14, 'ezr': 15,
    'neh': 16, 'est': 17, 'job': 18, 'psa': 19, 'pro': 20,
    'ecc': 21, 'sng': 22, 'isa': 23, 'jer': 24, 'lam': 25,
    'ezk': 26, 'dan': 27, 'hos': 28, 'jol': 29, 'amo': 30,
    'oba': 31, 'jon': 32, 'mic': 33, 'nam': 34, 'hab': 35,
    'zep': 36, 'hag': 37, 'zec': 38, 'mal': 39,
    'mat': 40, 'mrk': 41, 'luk': 42, 'jhn': 43, 'act': 44,
    'rom': 45, '1co': 46, '2co': 47, 'gal': 48, 'eph': 49,
    'php': 50, 'col': 51, '1th': 52, '2th': 53, '1ti': 54,
    '2ti': 55, 'tit': 56, 'phm': 57, 'heb': 58, 'jas': 59,
    '1pe': 60, '2pe': 61, '1jn': 62, '2jn': 63, '3jn': 64,
    'jud': 65, 'rev': 66,
  };

  /// Extracts book number, chapter number, and book abbreviation from a track name.
  static ({int? bookNumber, int? chapterNumber, String? bookAbbreviation})
      extractBookAndChapter(String trackName) {
    final stem = p.basenameWithoutExtension(trackName);

    // Extract all numbers
    final numberMatches = RegExp(r'\d+').allMatches(stem).map((m) => m.group(0)!).toList();

    // Extract word tokens for 3-letter book abbreviations
    final wordMatches = RegExp(r'[a-zA-Z]{3,4}').allMatches(stem).map((m) => m.group(0)!.toLowerCase()).toList();

    int? detectedBook;
    String? detectedAbbr;

    // Check words against Bible abbreviations
    for (final w in wordMatches) {
      if (bibleBookNumbers.containsKey(w)) {
        detectedBook = bibleBookNumbers[w];
        detectedAbbr = w.toUpperCase();
        break;
      }
    }

    int? bookNum;
    int? chapterNum;

    if (numberMatches.length >= 2) {
      final firstNum = int.tryParse(numberMatches[0]);
      final secondNum = int.tryParse(numberMatches[1]);

      // If first number is in standard 1..66 range
      if (firstNum != null && firstNum >= 1 && firstNum <= 66) {
        bookNum = firstNum;
        chapterNum = secondNum;
      } else if (detectedBook != null) {
        bookNum = detectedBook;
        chapterNum = firstNum;
      } else {
        chapterNum = secondNum;
      }
    } else if (numberMatches.length == 1) {
      final singleNum = int.tryParse(numberMatches[0]);
      if (detectedBook != null) {
        bookNum = detectedBook;
        chapterNum = singleNum;
      } else {
        chapterNum = singleNum;
      }
    } else if (detectedBook != null) {
      bookNum = detectedBook;
      chapterNum = 1;
    }

    return (
      bookNumber: bookNum ?? detectedBook,
      chapterNumber: chapterNum,
      bookAbbreviation: detectedAbbr,
    );
  }

  /// Automatically picks the best default ID style based on whether the track name
  /// contains recognizable Scripture book/chapter metadata.
  static IdGenerationStyle detectDefaultStyle(String trackName) {
    final parsed = extractBookAndChapter(trackName);
    if (parsed.bookNumber != null || parsed.bookAbbreviation != null) {
      return IdGenerationStyle.usfm8Digit;
    }
    return IdGenerationStyle.trackScoped;
  }

  /// Generates a single ID for the given line [lineIndex] (0-based).
  static String generateId({
    required IdGenerationStyle style,
    required String trackName,
    required int lineIndex,
    int? customBookNumber,
    int? customChapterNumber,
  }) {
    final verseNum = lineIndex + 1;

    switch (style) {
      case IdGenerationStyle.usfm8Digit:
        final parsed = extractBookAndChapter(trackName);
        final book = customBookNumber ?? parsed.bookNumber ?? 40;
        final chapter = customChapterNumber ?? parsed.chapterNumber ?? 1;

        final bStr = book.toString().padLeft(2, '0');
        final cStr = chapter.toString().padLeft(3, '0');
        final vStr = verseNum.toString().padLeft(3, '0');
        return '$bStr$cStr$vStr';

      case IdGenerationStyle.trackScoped:
        final stem = p.basenameWithoutExtension(trackName);
        final vStr = verseNum.toString().padLeft(3, '0');
        return '${stem}_$vStr';
    }
  }

  /// Generates preview IDs for display in UI.
  static List<String> generatePreview({
    required IdGenerationStyle style,
    required String trackName,
    int count = 3,
  }) {
    return List.generate(
      count,
      (i) => generateId(
        style: style,
        trackName: trackName,
        lineIndex: i,
      ),
    );
  }
}
