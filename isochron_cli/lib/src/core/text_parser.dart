import 'fragment.dart';

class TextParser {
  /// Parses raw text string into a list of Fragments.
  /// Splits primarily by newlines.
  static List<Fragment> parse(String rawText) {
    final List<Fragment> fragments = [];

    // Split by newline characters (handles Windows \r\n and Unix \n)
    final lines = rawText.split(RegExp(r'\r?\n'));

    int counter = 0;

    for (var line in lines) {
      final cleanLine = line.trim();

      // Skip empty lines
      if (cleanLine.isEmpty) {
        continue;
      }

      fragments.add(Fragment(
        index: counter,
        text: cleanLine,
      ));

      counter++;
    }

    return fragments;
  }
}
