import 'fragment.dart';

/// Checks whether a token matches common ID patterns:
/// - Digits only: e.g. "40001001", "1", "001"
/// - Numbers with verse letters/ranges: e.g. "1a", "4-5a"
/// - Section/intro codes: e.g. "s1", "is1"
/// - Verse notation: e.g. "1:1", "01.01"
/// - Verse prefix: e.g. "v1", "v12"
/// - Structured code notation: e.g. "MAT_1_1", "GEN.1.1", "MRK:1:1"
/// Plain words like "The", "In", "And" will return false.
bool isLikelyIdToken(String token) {
  if (token.isEmpty) return false;
  if (RegExp(r'^\d+$').hasMatch(token)) return true;
  if (RegExp(r'^\d+([a-z]|\-\d+[a-z]?)?$', caseSensitive: false).hasMatch(token)) {
    return true;
  }
  if (RegExp(r'^(s|is|ms|ip)\d+$', caseSensitive: false).hasMatch(token)) {
    return true;
  }
  if (RegExp(r'^\d+[:.]\d+$').hasMatch(token)) return true;
  if (RegExp(r'^v\d+$', caseSensitive: false).hasMatch(token)) return true;
  if (RegExp(r'^[a-zA-Z0-9]{2,5}[_.:]\d+([_.:]\d+)?$').hasMatch(token)) {
    return true;
  }
  return false;
}

/// Splits a phrase line into (id, text). Tries tab first since it's an
/// unambiguous delimiter (phrase text should never contain a literal tab);
/// falls back to splitting on the first run of whitespace only if the first
/// token matches a likely ID pattern (e.g. "40001001 In the beginning...").
/// Plain text lines without IDs (e.g. "In the beginning...") return (id: null, text: line).
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
    final candidateId = trimmed.substring(0, firstWs).trim();
    if (isLikelyIdToken(candidateId)) {
      final text = trimmed.substring(firstWs).trim();
      return (id: candidateId, text: text);
    }
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

/// Analyzes [text] to detect whether it contains embedded IDs (tab-delimited or space-delimited).
///
/// - Returns true if there is at least one non-empty line with a tab delimiter.
/// - Or if at least 60% of non-empty lines start with a recognizable ID token followed by whitespace.
bool detectEmbeddedIds(String text) {
  final lines = text
      .split(RegExp(r'\r?\n'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.isEmpty) return false;

  int tabCount = 0;
  int spaceIdCount = 0;

  for (final line in lines) {
    if (line.contains('\t')) {
      final idx = line.indexOf('\t');
      if (line.substring(0, idx).trim().isNotEmpty) {
        tabCount++;
      }
    } else {
      final firstWs = line.indexOf(RegExp(r'\s'));
      if (firstWs != -1) {
        final token = line.substring(0, firstWs).trim();
        if (isLikelyIdToken(token)) {
          spaceIdCount++;
        }
      }
    }
  }

  if (tabCount > 0) return true;
  return (spaceIdCount / lines.length) >= 0.6;
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

