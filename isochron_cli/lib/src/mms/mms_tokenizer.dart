import 'package:unorm_dart/unorm_dart.dart' as unorm;
import 'package:uroman/uroman.dart';

enum StarPlacement {
  /// Inserts '*' before verse 1, between every pair of verses, and after the last verse.
  segment,

  /// Inserts '*' only at the beginning and end of the entire track.
  edges,
}

class VerseTokenRange {
  final int verseIndex;
  final int tokenStartIndex;
  final int tokenEndIndex;
  final String romanizedText;
  final List<String> warnings;

  const VerseTokenRange({
    required this.verseIndex,
    required this.tokenStartIndex,
    required this.tokenEndIndex,
    required this.romanizedText,
    required this.warnings,
  });

  bool get isEmpty => tokenStartIndex >= tokenEndIndex;
  int get length => tokenEndIndex - tokenStartIndex;
}

class TokenizationOutput {
  final List<int> tokenIds;
  final List<String> tokenChars;
  final List<VerseTokenRange> verseRanges;

  const TokenizationOutput({
    required this.tokenIds,
    required this.tokenChars,
    required this.verseRanges,
  });
}

class MmsTokenizer {
  static const int blankTokenId = 0;
  static const int starTokenId = 31;
  static const String starChar = '*';

  static const Map<String, int> vocab = {
    '<blank>': 0,
    '<pad>': 1,
    '</s>': 2,
    '<unk>': 3,
    'a': 4,
    'i': 5,
    'e': 6,
    'n': 7,
    'o': 8,
    'u': 9,
    't': 10,
    's': 11,
    'r': 12,
    'm': 13,
    'k': 14,
    'l': 15,
    'd': 16,
    'g': 17,
    'h': 18,
    'y': 19,
    'b': 20,
    'p': 21,
    'w': 22,
    'c': 23,
    'v': 24,
    'j': 25,
    'z': 26,
    'f': 27,
    "'": 28,
    'q': 29,
    'x': 30,
    '*': 31,
  };

  final Uroman _uroman;
  static final RegExp _combiningMarksRegex =
      RegExp(r'[\u0300-\u036f\u1dc0-\u1dff\u20d0-\u20ff]');
  static final RegExp _digitRegex = RegExp(r'[0-9]');

  MmsTokenizer({Uroman? uroman}) : _uroman = uroman ?? Uroman();

  /// Romanizes and normalizes a single string.
  /// Returns the cleaned string containing only [a-z'] and spaces,
  /// plus any warnings (e.g. dropped digits).
  ({String normalized, List<String> warnings}) normalizeText(
    String text, {
    String? languageCode,
  }) {
    final warnings = <String>[];

    // 1. Uroman romanization
    final romanized = _uroman.romanizeString(
      text,
      lcode: languageCode != null && languageCode.isNotEmpty ? languageCode : null,
    );

    // 2. Unicode decomposition (NFKD) and diacritic stripping
    final decomposed = unorm.nfkd(romanized);
    final stripped = decomposed.replaceAll(_combiningMarksRegex, '');

    // 3. Lowercase and filter
    final lower = stripped.toLowerCase();
    final buffer = StringBuffer();

    final droppedDigits = <String>{};
    for (var i = 0; i < lower.length; i++) {
      final char = lower[i];
      if ((char.codeUnitAt(0) >= 97 && char.codeUnitAt(0) <= 122) || char == "'") {
        buffer.write(char);
      } else if (_digitRegex.hasMatch(char)) {
        droppedDigits.add(char);
      } else {
        // Space, punctuation, dash -> whitespace word separator
        buffer.write(' ');
      }
    }

    if (droppedDigits.isNotEmpty) {
      warnings.add('Digits dropped from text: ${droppedDigits.toList()..sort()}');
    }

    // Collapse multiple spaces into single space and trim
    final cleaned = buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty && text.trim().isNotEmpty) {
      warnings.add('empty_text: no alignable phonetic characters remaining');
    }

    return (normalized: cleaned, warnings: warnings);
  }

  /// Tokenizes a list of verse/phrase texts into target MMS token IDs.
  TokenizationOutput tokenizeVerses(
    List<String> verses, {
    String? languageCode,
    StarPlacement starPlacement = StarPlacement.segment,
  }) {
    final tokenIds = <int>[];
    final tokenChars = <String>[];
    final verseRanges = <VerseTokenRange>[];

    void appendStar() {
      tokenIds.add(starTokenId);
      tokenChars.add(starChar);
    }

    // Lead star token
    appendStar();

    for (var v = 0; v < verses.length; v++) {
      final verseText = verses[v];
      final normResult = normalizeText(verseText, languageCode: languageCode);
      final normalized = normResult.normalized;

      final startIndex = tokenIds.length;

      // Convert characters into token IDs (ignoring whitespace between words)
      for (var i = 0; i < normalized.length; i++) {
        final char = normalized[i];
        if (char == ' ') continue; // whitespace is inter-word, blank-handled

        final id = vocab[char];
        if (id != null) {
          tokenIds.add(id);
          tokenChars.add(char);
        }
      }

      final endIndex = tokenIds.length;
      final warnings = List<String>.from(normResult.warnings);
      if (startIndex == endIndex) {
        warnings.add('empty_verse: verse produced zero alignment tokens');
      }

      verseRanges.add(
        VerseTokenRange(
          verseIndex: v,
          tokenStartIndex: startIndex,
          tokenEndIndex: endIndex,
          romanizedText: normalized,
          warnings: warnings,
        ),
      );

      // In segment mode, append star after every verse
      if (starPlacement == StarPlacement.segment) {
        appendStar();
      }
    }

    // In edges mode, append trailing star if not already appended
    if (starPlacement == StarPlacement.edges) {
      appendStar();
    }

    return TokenizationOutput(
      tokenIds: tokenIds,
      tokenChars: tokenChars,
      verseRanges: verseRanges,
    );
  }
}
