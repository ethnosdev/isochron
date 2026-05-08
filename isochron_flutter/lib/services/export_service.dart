import 'dart:convert';
import 'dart:io';

import 'package:isochron_cli/isochron_cli.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:path/path.dart' as p;

class ExportService {
  /// Builds the "Export Combined CSV" payload for the whole project.
  static Future<String> buildCombinedCsv(Project project) async {
    final exportableTracks = project.collections
        .expand((c) => c.tracks)
        .where((t) => isPhraseExportableStatus(t.status))
        .toList();

    if (exportableTracks.isEmpty) return '';

    final buffer = StringBuffer();
    buffer.writeln('id,verse_id,recording_id,start,end');

    for (final track in exportableTracks) {
      final entries = await _loadAlignmentEntries(project, track);
      if (entries.isEmpty) continue;

      final displayTitle = track.audioPath != null
          ? p.basenameWithoutExtension(track.audioPath!)
          : track.name;

      buffer.write(generateCsv(entries, displayTitle, includeHeader: false));
    }

    return buffer.toString();
  }

  /// Builds the phrase-timing payload for a single track.
  static Future<String?> buildPhraseTiming(Project project, Track track) async {
    if (!canExportPhraseTiming(track)) return null;

    final entries = await _loadAlignmentEntries(project, track);
    if (entries.isEmpty) return null;

    final metadata = parsePhraseMetadataFromTextFilename(track.textPath);
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

  /// Serializes a list of alignment rows into phrase timing text format
  static String generatePhraseTiming(
    List<Map<String, dynamic>> entries,
    TimingExportMetadata metadata,
  ) {
    return TimingExport.generateTimingPayload(
      _entriesToFragments(entries),
      metadata,
    );
  }

  /// Parses phrase metadata from a source text filename convention
  static TimingExportMetadata parsePhraseMetadataFromTextFilename(
    String? textPath,
  ) {
    return TimingExport.parseMetadataFromSourceFilename(textPath);
  }

  static String defaultPhraseTimingFilename(TimingExportMetadata metadata) {
    return '${metadata.languageCode}-${metadata.bookId}-${metadata.bookCode}-${metadata.chapterId}.txt';
  }

  static String defaultPhraseTimingFilenameForTrack(Track track) {
    return TimingExport.defaultTimingFilenameFromSourcePath(track.textPath);
  }

  static String defaultCsvFilename(String projectName) {
    return '${projectName.replaceAll(" ", "_")}_full.csv';
  }

  static bool isPhraseExportableStatus(AlignmentStatus status) {
    return status == AlignmentStatus.done || status == AlignmentStatus.reviewed;
  }

  /// Phrase export is enabled when alignment status is finalized.
  static bool canExportPhraseTiming(Track track) {
    return isPhraseExportableStatus(track.status);
  }

  static String phraseExportTooltip(Track track) {
    if (!isPhraseExportableStatus(track.status)) {
      return 'Export is available only for Done/Reviewed alignments';
    }
    return 'Export phrase timing';
  }

  static String _escape(String input) {
    if (input.contains(',')) return '"$input"';
    return input;
  }

  /// Reads per-alignment JSON output persisted by the aligner.
  static Future<List<Map<String, dynamic>>> _loadAlignmentEntries(
    Project project,
    Track track,
  ) async {
    final absJsonPath = track.getAbsoluteOutputPath(project.directoryPath);
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
