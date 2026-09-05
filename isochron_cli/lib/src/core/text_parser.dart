import 'fragment.dart';

/// Splits a phrase line into (id, text). Tries tab first since it's an
/// unambiguous delimiter (phrase text should never contain a literal tab);
/// falls back to splitting on the first run of whitespace for legacy
/// space-delimited files (e.g. "40001001 In the beginning...").
({String? id, String text}) splitIdAndText(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return (id: null, text: '');

  if (trimmed.contains('\t')) {
    final idx = trimmed.indexOf('\t');
    final id = trimmed.substring(0, idx).trim();
    final text = trimmed.substring(idx + 1).trim();
    return (id: id.isEmpty ? null : id, text: text);
  }

  final firstWs = trimmed.indexOf(RegExp(r'\s'));
  if (firstWs != -1) {
    final id = trimmed.substring(0, firstWs).trim();
    final text = trimmed.substring(firstWs).trim();
    return (id: id.isEmpty ? null : id, text: text);
  }
  return (id: null, text: trimmed);
}

/// Returns true if [text] contains at least one non-empty line with a tab delimiter.
bool detectTabDelimitedIds(String text) {
  final lines = text.split(RegExp(r'\r?\n'));
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isNotEmpty && trimmed.contains('\t')) {
      final idx = trimmed.indexOf('\t');
      final id = trimmed.substring(0, idx).trim();
      if (id.isNotEmpty) return true;
    }
  }
  return false;
}

class TextParser {
  /// Parses raw text string into a list of Fragments.
  /// Splits primarily by newlines.
  /// If [hasIds] is true, extracts phrase IDs using [splitIdAndText].
  static List<Fragment> parse(String rawText, {bool hasIds = false}) {
    final List<Fragment> fragments = [];

    // Split by newline characters (handles Windows \r\n and Unix \n)
    final lines = rawText.split(RegExp(r'\r?\n'));

    int counter = 0;

    for (var line in lines) {
      final cleanLine = line.trim();

      if (cleanLine.isEmpty) {
        continue;
      }

      if (hasIds) {
        final parsed = splitIdAndText(cleanLine);
        fragments.add(Fragment(
          index: counter,
          id: parsed.id,
          text: parsed.text,
        ));
      } else {
        fragments.add(Fragment(
          index: counter,
          text: cleanLine,
        ));
      }

      counter++;
    }

    return fragments;
  }
}

