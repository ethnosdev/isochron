import 'dart:convert';
import 'dart:io';

import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:path/path.dart' as p;

class PhraseExportMetadata {
  final String languageCode;
  final String bookId;
  final String bookCode;
  final String chapterId;

  const PhraseExportMetadata({
    required this.languageCode,
    required this.bookId,
    required this.bookCode,
    required this.chapterId,
  });

  static const PhraseExportMetadata fallback = PhraseExportMetadata(
    languageCode: 'XX',
    bookId: '00',
    bookCode: 'BOOK',
    chapterId: '1',
  );
}

class ExportService {
  /// Builds the "Export Combined CSV" payload for the whole project.
  ///
  /// This intentionally exports only alignments that are finalized enough for
  /// downstream use (`done` / `reviewed`) to match existing product behavior.
  static Future<String> buildCombinedCsv(Project project) async {
    final exportablePairs = project.alignments
        .where((p) => isPhraseExportableStatus(p.status))
        .toList();
    if (exportablePairs.isEmpty) return '';

    final buffer = StringBuffer();
    buffer.writeln('id,verse_id,recording_id,start,end');

    for (final pair in exportablePairs) {
      final entries = await _loadAlignmentEntries(project, pair);
      if (entries.isEmpty) continue;

      final audioAsset = project.audioPool
          .where((a) => a.id == pair.audioAssetId)
          .firstOrNull;
      final displayTitle = audioAsset != null
          ? p.basenameWithoutExtension(audioAsset.path)
          : pair.id;

      buffer.write(generateCsv(entries, displayTitle, includeHeader: false));
    }

    return buffer.toString();
  }

  /// Builds the phrase-timing payload for a single alignment pair.
  ///
  /// Returns `null` when export is not allowed (status) or when the
  /// alignment JSON has no rows.
  static Future<String?> buildPhraseTiming(Project project, AlignmentPair pair) async {
    if (!canExportPhraseTiming(pair)) return null;

    final entries = await _loadAlignmentEntries(project, pair);
    if (entries.isEmpty) return null;

    final textAsset = project.textPool
        .where((a) => a.id == pair.textAssetId)
        .firstOrNull;
    final metadata = parsePhraseMetadataFromTextFilename(textAsset?.path);
    return generatePhraseTiming(entries, metadata);
  }

  /// Serializes a list of alignment rows into the shared CSV schema.
  static String generateCsv(
    List<Map<String, dynamic>> entries,
    String recordingId, {
    bool includeHeader = true,
  }) {
    final buffer = StringBuffer();
    if (includeHeader) {
      buffer.writeln('id,verse_id,recording_id,start,end');
    }

    for (final e in entries) {
      buffer.write('${e['index']},');
      buffer.write('${e['id'] ?? ""},');
      buffer.write('${_escape(recordingId)},');
      buffer.write('${e['start']},');
      buffer.write('${e['end']}\n');
    }

    return buffer.toString();
  }

  /// Serializes a list of alignment rows into phrase timing text format:
  /// `\id`, `\c`, `\level phrase`, then `<start> <end> <phraseId>` rows.
  static String generatePhraseTiming(
    List<Map<String, dynamic>> entries,
    PhraseExportMetadata metadata,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('\\id ${metadata.bookCode}');
    buffer.writeln('\\c ${metadata.chapterId}');
    buffer.writeln('\\level phrase');

    for (int i = 0; i < entries.length; i++) {
      final e = entries[i];
      final phraseId = _resolvePhraseId(e, i);
      final start = _formatSeconds(e['start']);
      final end = _formatSeconds(e['end']);
      buffer.writeln('$start\t$end\t$phraseId');
    }

    return buffer.toString();
  }

  /// Parses phrase metadata from a source text filename convention:
  /// `LANG-BOOKID-BOOK-CHAPTERID.*`.
  ///
  /// Extension is ignored intentionally so both `.txt` and `.phrase` source
  /// files can provide naming hints.
  static PhraseExportMetadata parsePhraseMetadataFromTextFilename(String? textPath) {
    if (textPath == null || textPath.trim().isEmpty) {
      return PhraseExportMetadata.fallback;
    }

    final base = p.basenameWithoutExtension(textPath);
    final separator = _detectFilenameSeparator(base);
    final parts = _splitBySeparator(base, separator);
    if (parts.length < 4) return PhraseExportMetadata.fallback;

    final languageCode = parts[0].trim();
    final bookId = parts[1].trim();
    // Support optional trailing suffix tokens (e.g. "..._01_read") by taking
    // the rightmost numeric token as chapter id.
    final chapterIdx = _findChapterTokenIndex(parts);
    if (chapterIdx <= 2) return PhraseExportMetadata.fallback;
    final chapterId = parts[chapterIdx].trim();
    final bookCode = parts.sublist(2, chapterIdx).join('-').trim();

    if (languageCode.isEmpty || bookId.isEmpty || bookCode.isEmpty || chapterId.isEmpty) {
      return PhraseExportMetadata.fallback;
    }

    return PhraseExportMetadata(
      languageCode: languageCode,
      bookId: bookId,
      bookCode: bookCode,
      chapterId: chapterId,
    );
  }

  static String defaultPhraseTimingFilename(PhraseExportMetadata metadata) {
    return '${metadata.languageCode}-${metadata.bookId}-${metadata.bookCode}-${metadata.chapterId}.txt';
  }

  static String defaultPhraseTimingFilenameForPair(
    Project project,
    AlignmentPair pair,
  ) {
    final textAsset = project.textPool
        .where((a) => a.id == pair.textAssetId)
        .firstOrNull;
    if (textAsset == null || textAsset.path.trim().isEmpty) {
      return defaultPhraseTimingFilename(PhraseExportMetadata.fallback);
    }

    final inputBase = p.basenameWithoutExtension(textAsset.path);
    final detected = _detectFilenameSeparator(inputBase);
    final outputSep = detected == ' ' ? '-' : detected;

    // Timing exports are always plain text sidecars.
    return '$inputBase${outputSep}timing.txt';
  }

  static String defaultCsvFilename(String projectName) {
    return '${projectName.replaceAll(" ", "_")}_full.csv';
  }

  static bool isPhraseExportableStatus(AlignmentStatus status) {
    return status == AlignmentStatus.done || status == AlignmentStatus.reviewed;
  }

  /// Phrase export is enabled when alignment status is finalized.
  static bool canExportPhraseTiming(AlignmentPair pair) {
    return isPhraseExportableStatus(pair.status);
  }

  /// User-facing tooltip reason for export button state.
  /// Keep this centralized so toolbar and batch tiles stay consistent.
  static String phraseExportTooltip(AlignmentPair pair) {
    if (!isPhraseExportableStatus(pair.status)) {
      return 'Export is available only for Done/Reviewed alignments';
    }
    if (canExportPhraseTiming(pair)) {
      return 'Export phrase timing';
    }
    return 'Export unavailable';
  }

  static String _resolvePhraseId(Map<String, dynamic> entry, int index) {
    final id = entry['id']?.toString().trim();
    if (id != null && id.isNotEmpty) return id;
    return '${index + 1}';
  }

  static String _formatSeconds(dynamic value) {
    final asNum = value is num ? value.toDouble() : double.tryParse(value.toString()) ?? 0.0;
    return asNum.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  static String _escape(String input) {
    if (input.contains(',')) return '"$input"';
    return input;
  }

  static String _detectFilenameSeparator(String value) {
    final dashCount = '-'.allMatches(value).length;
    final underscoreCount = '_'.allMatches(value).length;
    final spaceCount = ' '.allMatches(value).length;
    if (dashCount == 0 && underscoreCount == 0 && spaceCount == 0) return '-';

    final counts = {'-': dashCount, '_': underscoreCount, ' ': spaceCount};
    final best = counts.entries.reduce(
      (a, b) => a.value >= b.value ? a : b,
    );
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

  /// Reads per-alignment JSON output persisted by the aligner.
  static Future<List<Map<String, dynamic>>> _loadAlignmentEntries(
    Project project,
    AlignmentPair pair,
  ) async {
    final absJsonPath = pair.getAbsoluteOutputPath(project.directoryPath);
    final file = File(absJsonPath);
    if (!await file.exists()) return [];

    final content = await file.readAsString();
    final List<dynamic> jsonList = jsonDecode(content);
    return jsonList
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
}
