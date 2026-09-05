import 'package:isochron_cli/isochron_cli.dart';

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
/// Supports tab delimiter as well as whitespace separators.
/// If no ID/content boundary is found, the original line is returned as content.
ParsedIdLine extractIdFromLine(String line) {
  final parsed = splitIdAndText(line);
  if (parsed.id != null) {
    return ParsedIdLine(
      id: parsed.id!,
      content: parsed.text,
      hasId: true,
    );
  }
  return ParsedIdLine(
    id: '',
    content: parsed.text,
    hasId: false,
  );
}

