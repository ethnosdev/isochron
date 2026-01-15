import 'package:unorm_dart/unorm_dart.dart' as unorm;

class Transliterator {
  /// 1. Decomposes Unicode (NFD).
  /// 2. Removes Diacritics (Accents/Breathings).
  /// 3. Maps base characters using [dictionary].
  static String convert(String input, Map<String, String> dictionary) {
    if (dictionary.isEmpty) return input;

    final buffer = StringBuffer();

    // Step A: Normalize to NFD (Decompose)
    // "ά" becomes "α" + " ́ "
    String decomposed = unorm.nfd(input);

    // Step B: Remove Combining Diacritical Marks
    // Unicode block \u0300-\u036f covers standard accents/breathings
    // Unicode block \u1dc0-\u1dff and \u20d0-\u20ff cover others
    final diacriticsRegex =
        RegExp(r'[\u0300-\u036f\u1dc0-\u1dff\u20d0-\u20ff]');
    String cleanText = decomposed.replaceAll(diacriticsRegex, '');

    // Note: Iota subscript (terminating in \u0345) is also a combining mark
    // and will be removed by the regex above.
    // Result: ᾷ -> α

    // Step C: Map base characters
    for (int i = 0; i < cleanText.length; i++) {
      final char = cleanText[i];
      buffer.write(dictionary[char] ?? char);
    }

    return buffer.toString();
  }
}
