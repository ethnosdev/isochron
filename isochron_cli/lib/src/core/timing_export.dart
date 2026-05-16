import 'package:path/path.dart' as p;

import 'fragment.dart';

enum CliOutputFormat { json, timing }

class TimingExportMetadata {
  final String languageCode;
  final String bookId;
  final String bookCode;
  final String chapterId;

  const TimingExportMetadata({
    required this.languageCode,
    required this.bookId,
    required this.bookCode,
    required this.chapterId,
  });

  static const fallback = TimingExportMetadata(
    languageCode: 'XX',
    bookId: '00',
    bookCode: 'BOOK',
    chapterId: '1',
  );
}

class TimingExport {
  /// Resolves the final output contract in one place for all callers:
  /// - picks effective format (explicit `--format` > extension inference),
  /// - derives a default filename when no explicit output is provided,
  /// - normalizes extension so filename always matches actual content type.
  static ({CliOutputFormat format, String outputPath}) resolveEffectiveOutput({
    required String? explicitOutputPath,
    required String? requestedFormat,
    required String? sourceTextPath,
  }) {
    final format = resolveOutputFormat(
      outputPath: explicitOutputPath ?? '',
      requestedFormat: requestedFormat,
    );
    final rawPath = explicitOutputPath ??
        (format == CliOutputFormat.timing
            ? defaultTimingFilenameFromSourcePath(sourceTextPath)
            : defaultJsonFilenameFromSourcePath(sourceTextPath));
    final normalizedPath =
        normalizeOutputPathForFormat(outputPath: rawPath, format: format);
    return (format: format, outputPath: normalizedPath);
  }

  /// Parses `LANG-BOOKID-BOOK-CHAPTER[_SUFFIX]` style source names.
  ///
  /// Parsing is separator-tolerant (`-`, `_`, whitespace) and suffix-tolerant
  /// by using the rightmost numeric token as chapter id.
  static TimingExportMetadata parseMetadataFromSourceFilename(
    String? sourcePath,
  ) {
    if (sourcePath == null || sourcePath.trim().isEmpty) {
      return TimingExportMetadata.fallback;
    }

    final base = p.basenameWithoutExtension(sourcePath);
    final separator = _detectFilenameSeparator(base);
    final parts = _splitBySeparator(base, separator);
    if (parts.length < 4) return TimingExportMetadata.fallback;

    final languageCode = parts[0].trim();
    final bookId = parts[1].trim();
    final chapterIdx = _findChapterTokenIndex(parts);
    if (chapterIdx <= 2) return TimingExportMetadata.fallback;

    final chapterId = parts[chapterIdx].trim();
    final bookCode = parts.sublist(2, chapterIdx).join('-').trim();
    if (languageCode.isEmpty ||
        bookId.isEmpty ||
        chapterId.isEmpty ||
        bookCode.isEmpty) {
      return TimingExportMetadata.fallback;
    }

    return TimingExportMetadata(
      languageCode: languageCode,
      bookId: bookId,
      bookCode: bookCode,
      chapterId: chapterId,
    );
  }

  static String generateTimingPayload(
    List<Fragment> fragments,
    TimingExportMetadata metadata,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('\\id ${metadata.bookCode}');
    buffer.writeln('\\c ${metadata.chapterId}');
    buffer.writeln('\\level phrase');

    for (int i = 0; i < fragments.length; i++) {
      final f = fragments[i];
      final phraseId = _resolvePhraseId(f, i);
      final start = _formatSeconds(f.realStart);
      final end = _formatSeconds(f.realEnd);
      buffer.writeln('$start\t$end\t$phraseId');
    }

    return buffer.toString();
  }

  static String defaultTimingFilenameFromSourcePath(String? sourcePath) {
    if (sourcePath == null || sourcePath.trim().isEmpty) {
      return 'BOOK-1-timing.txt';
    }

    final inputBase = p.basenameWithoutExtension(sourcePath);
    final detected = _detectFilenameSeparator(inputBase);
    final outputSep = detected == ' ' ? '-' : detected;
    return '$inputBase${outputSep}timing.txt';
  }

  static String defaultJsonFilenameFromSourcePath(String? sourcePath) {
    if (sourcePath == null || sourcePath.trim().isEmpty) {
      return 'alignment.json';
    }
    // Match UI-style behavior: start from source text base name.
    final inputBase = p.basenameWithoutExtension(sourcePath);
    if (inputBase.trim().isEmpty) return 'alignment.json';
    return '$inputBase.json';
  }

  static CliOutputFormat resolveOutputFormat({
    required String outputPath,
    String? requestedFormat,
  }) {
    // Explicit --format always wins; extension inference is fallback behavior.
    final normalized = requestedFormat?.trim().toLowerCase();
    if (normalized == 'timing') return CliOutputFormat.timing;
    if (normalized == 'json') return CliOutputFormat.json;

    final ext = p.extension(outputPath).toLowerCase();
    if (ext == '.txt') return CliOutputFormat.timing;
    return CliOutputFormat.json;
  }

  static String normalizeOutputPathForFormat({
    required String outputPath,
    required CliOutputFormat format,
  }) {
    // Keep the saved filename extension aligned with the resolved format so
    // callers never get JSON content in a .txt (or timing in a .json) file.
    final expectedExtension = format == CliOutputFormat.json ? '.json' : '.txt';
    final currentExtension = p.extension(outputPath).toLowerCase();
    if (currentExtension == expectedExtension) return outputPath;
    return p.setExtension(outputPath, expectedExtension);
  }

  static String _resolvePhraseId(Fragment fragment, int index) {
    final id = fragment.id?.trim();
    if (id != null && id.isNotEmpty) return id;
    return '${index + 1}';
  }

  static String _formatSeconds(double value) {
    return value.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  static String _detectFilenameSeparator(String value) {
    final dashCount = '-'.allMatches(value).length;
    final underscoreCount = '_'.allMatches(value).length;
    final spaceCount = ' '.allMatches(value).length;
    if (dashCount == 0 && underscoreCount == 0 && spaceCount == 0) return '-';

    final counts = {'-': dashCount, '_': underscoreCount, ' ': spaceCount};
    final best = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return best.key;
  }

  static List<String> _splitBySeparator(String value, String separator) {
    if (separator == ' ') {
      return value
          .trim()
          .split(RegExp(r'\s+'))
          .where((p) => p.isNotEmpty)
          .toList();
    }
    return value.split(separator).where((p) => p.isNotEmpty).toList();
  }

  static int _findChapterTokenIndex(List<String> parts) {
    for (int i = parts.length - 1; i >= 0; i--) {
      if (RegExp(r'^\d+$').hasMatch(parts[i].trim())) {
        return i;
      }
    }
    return -1;
  }
}
