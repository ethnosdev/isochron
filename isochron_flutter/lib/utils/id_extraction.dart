class ParsedIdLine {
  final String id;
  final String content;
  final bool hasId;

  const ParsedIdLine({
    required this.id,
    required this.content,
    required this.hasId,
  });
}

/// Extracts a leading ID from a transcript line when present.
///
/// Supports any whitespace separator (spaces, tabs, mixed whitespace).
/// If no ID/content boundary is found, the original line is returned as content.
ParsedIdLine extractIdFromLine(String line) {
  final match = RegExp(r'^\s*(\S+)\s+(.+?)\s*$').firstMatch(line);
  if (match == null) {
    return ParsedIdLine(id: '', content: line, hasId: false);
  }

  return ParsedIdLine(
    id: match.group(1) ?? '',
    content: match.group(2) ?? '',
    hasId: true,
  );
}
