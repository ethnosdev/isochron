import 'package:unorm_dart/unorm_dart.dart' as unorm;

class Transliterator {
  static String convert(String input, Map<String, String> dictionary) {
    if (dictionary.isEmpty) return input;

    final buffer = StringBuffer();
    // Regex for Unicode Combining Diacritical Marks
    final diacriticsRegex =
        RegExp(r'[\u0300-\u036f\u1dc0-\u1dff\u20d0-\u20ff]');

    // sort keys by length to ensure longer matches are checked first (e.g. "ñ" before "n")
    final sortedKeys = dictionary.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    // PRIORITY 1: Specific Override
    // Example: User wants "ñ" to be "ny"
    // FIRST, apply any direct string replacements from the dictionary (for multi-char mappings)
    for (String key in sortedKeys) {
      input = input.replaceAll(key, dictionary[key]!);
    }

    // Iterate through characters.
    // Note: iterating by characters is safer for unicode, but for simplicity
    // in this scope, standard iteration usually works for European scripts.
    for (int i = 0; i < input.length; i++) {
      String char = input[i];

      // If the character was already converted to Latin above, just append it
      if (RegExp(r'[a-zA-Z0-9\s\.,;!?\n\r]').hasMatch(char)) {
        buffer.write(char);
        continue;
      }

      // PRIORITY 2: Decompose & Strip
      // Example: "ά" (not in dict) becomes "α" + "tonos"
      String decomposed = unorm.nfd(char);
      String stripped = decomposed.replaceAll(diacriticsRegex, '');

      // PRIORITY 3: Base Mapping
      // Example: Now we have "α", check if that is in dict.
      if (dictionary.containsKey(stripped)) {
        buffer.write(dictionary[stripped]);
      } else {
        // skip characters that can't be transliterated
      }
    }

    return buffer.toString();
  }
}
