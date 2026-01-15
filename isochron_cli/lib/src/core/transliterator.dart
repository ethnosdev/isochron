import 'package:unorm_dart/unorm_dart.dart' as unorm;

class Transliterator {
  static String convert(String input, Map<String, String> dictionary) {
    if (dictionary.isEmpty) return input;

    final buffer = StringBuffer();
    // Regex for Unicode Combining Diacritical Marks
    final diacriticsRegex =
        RegExp(r'[\u0300-\u036f\u1dc0-\u1dff\u20d0-\u20ff]');

    // Iterate through characters.
    // Note: iterating by characters is safer for unicode, but for simplicity
    // in this scope, standard iteration usually works for European scripts.
    for (int i = 0; i < input.length; i++) {
      String char = input[i];

      // PRIORITY 1: Specific Override
      // Example: User wants "ñ" to be "ny"
      if (dictionary.containsKey(char)) {
        buffer.write(dictionary[char]);
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
        // Fallback: Just keep the stripped Latin/Base char
        // Example: "é" -> "e" (if user didn't provide a rule for é or e)
        buffer.write(stripped);
      }
    }

    return buffer.toString();
  }
}
