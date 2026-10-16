import 'package:uroman/uroman.dart';

/// Universal romanization utility powered by `package:uroman`.
///
/// Determines if text is written in a non-Latin script and converts it to
/// a romanized Latin script.
class Romanizer {
  static final Uroman _uroman = Uroman();

  /// Checks if [text] is already written in a romanized script (Latin).
  ///
  /// Returns `true` if all script-identifiable characters in [text] belong to the
  /// Latin script (e.g. English, Spanish, French, German, Vietnamese), or if the
  /// text contains no script-specific characters (such as numbers or punctuation).
  ///
  /// Returns `false` if [text] contains any characters from a non-Latin script
  /// (e.g. Greek, Hebrew, Cyrillic, Arabic, Devanagari, CJK, Ethiopic, etc.).
  static bool isAlreadyRomanized(String text) {
    if (text.trim().isEmpty) return true;
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      final script = _uroman.data.charToScript[ch];
      if (script != null && script.toLowerCase() != 'latin') {
        return false;
      }
    }
    return true;
  }

  /// Romanizes [text] using uroman if it is not already in a romanized script.
  ///
  /// Returns `null` if the text is already romanized (or empty), or if romanization
  /// yields a string identical to the original text.
  ///
  /// An optional [languageCode] (ISO 639-3, e.g. `'ell'`, `'heb'`) can be provided
  /// to guide script/language-specific transliteration rules.
  static String? romanize(String text, {String? languageCode}) {
    if (isAlreadyRomanized(text)) return null;
    final romanized = _uroman.romanizeString(
      text,
      lcode: languageCode != null && languageCode.isNotEmpty ? languageCode : null,
    );
    if (romanized.trim() == text.trim()) return null;
    return romanized;
  }
}
