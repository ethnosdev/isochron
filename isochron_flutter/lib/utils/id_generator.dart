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
    final tokens = stem
        .split(RegExp(r'[\s_\-.]+'))
        .where((t) => t.isNotEmpty)
        .toList();

    int? detectedBook;
    String? detectedAbbr;
    int? bookTokenIndex;

    // Match whole tokens against Bible abbreviations (including numbered books like 1Sa, 2Co, 3Jn).
    for (int i = 0; i < tokens.length; i++) {
      final lower = tokens[i].toLowerCase();
      if (bibleBookNumbers.containsKey(lower)) {
        detectedBook = bibleBookNumbers[lower];
        detectedAbbr = lower.toUpperCase();
        bookTokenIndex = i;
        break;
      }
    }

    // Only consider purely numeric tokens so leading digits in abbreviations (e.g. "1" in "1Sa")
    // are never mistaken for book or chapter numbers.
    final numericTokens = <({int index, int value})>[];
    for (int i = 0; i < tokens.length; i++) {
      if (RegExp(r'^\d+$').hasMatch(tokens[i])) {
        final parsed = int.tryParse(tokens[i]);
        if (parsed != null) {
          numericTokens.add((index: i, value: parsed));
        }
      }
    }

    int? bookNum;
    int? chapterNum;

    if (bookTokenIndex != null && detectedBook != null) {
      bookNum = detectedBook;
      final afterBook =
          numericTokens.where((n) => n.index > bookTokenIndex!).toList();
      if (afterBook.isNotEmpty) {
        chapterNum = afterBook.first.value;
      } else {
        final beforeBook =
            numericTokens.where((n) => n.index < bookTokenIndex!).toList();
        if (beforeBook.length >= 2) {
          chapterNum = beforeBook.last.value;
        } else if (beforeBook.length == 1 &&
            beforeBook.first.value != detectedBook) {
          chapterNum = beforeBook.first.value;
        } else {
          chapterNum = 1;
        }
      }
    } else if (numericTokens.length >= 2) {
      final firstNum = numericTokens[0].value;
      final secondNum = numericTokens[1].value;
      if (firstNum >= 1 && firstNum <= 66) {
        bookNum = firstNum;
        chapterNum = secondNum;
      } else {
        chapterNum = secondNum;
      }
    } else if (numericTokens.length == 1) {
      chapterNum = numericTokens[0].value;
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
