import 'dart:convert';
import 'dart:io';

import 'package:isochron_cli/isochron_cli.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:path/path.dart' as p;

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
  static Future<String?> buildPhraseTiming(
    Project project,
    AlignmentPair pair,
  ) async {
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
    TimingExportMetadata metadata,
  ) {
    return TimingExport.generateTimingPayload(
      _entriesToFragments(entries),
      metadata,
    );
  }

  /// Parses phrase metadata from a source text filename convention:
  /// `LANG-BOOKID-BOOK-CHAPTERID.*`.
  ///
  /// Extension is ignored intentionally so both `.txt` and `.phrase` source
  /// files can provide naming hints.
  static TimingExportMetadata parsePhraseMetadataFromTextFilename(
    String? textPath,
  ) {
    return TimingExport.parseMetadataFromSourceFilename(textPath);
  }

  static String defaultPhraseTimingFilename(TimingExportMetadata metadata) {
    return '${metadata.languageCode}-${metadata.bookId}-${metadata.bookCode}-${metadata.chapterId}.txt';
  }

  static String defaultPhraseTimingFilenameForPair(
    Project project,
    AlignmentPair pair,
  ) {
    final textAsset = project.textPool
        .where((a) => a.id == pair.textAssetId)
        .firstOrNull;
    return TimingExport.defaultTimingFilenameFromSourcePath(textAsset?.path);
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

  static String _escape(String input) {
    if (input.contains(',')) return '"$input"';
    return input;
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

  static List<Fragment> _entriesToFragments(
    List<Map<String, dynamic>> entries,
  ) {
    return entries.map((e) {
      final fragment = Fragment(
        index: (e['index'] as num?)?.toInt() ?? 0,
        id: e['id']?.toString(),
        text: e['text']?.toString() ?? '',
      );
      fragment.setRealTiming(
        start: (e['start'] as num?)?.toDouble() ?? 0.0,
        end: (e['end'] as num?)?.toDouble() ?? 0.0,
      );
      return fragment;
    }).toList();
  }
}
