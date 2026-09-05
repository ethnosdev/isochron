import 'dart:convert';
import 'dart:io';

import 'package:isochron_cli/isochron_cli.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';

class ExportService {
  /// Builds the phrase-timing payload for a single track.
  static Future<String?> buildPhraseTiming(
    Project project,
    Track track, {
    bool? requireIds,
  }) async {
    if (!canExportPhraseTiming(track)) return null;

    final entries = await _loadAlignmentEntries(project, track);
    if (entries.isEmpty) return null;

    final metadata = parsePhraseMetadataFromTextFilename(track.textPath);
    return generatePhraseTiming(
      entries,
      metadata,
      requireIds: requireIds ??
          (project.defaultHasIds || project.defaultGenerateIds),
    );
  }

  /// Serializes a list of alignment rows into phrase timing text format
  static String generatePhraseTiming(
    List<Map<String, dynamic>> entries,
    TimingExportMetadata metadata, {
    bool requireIds = false,
  }) {
    return TimingExport.generateTimingPayload(
      _entriesToFragments(entries),
      metadata,
      requireIds: requireIds,
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

  /// Reads per-alignment JSON output persisted by the aligner.
  static Future<List<Map<String, dynamic>>> _loadAlignmentEntries(
    Project project,
    Track track,
  ) async {
    // Find the collection to extract the friendly folderName
    final collection = project.collections.firstWhere(
      (c) => c.id == track.collectionId,
      orElse: () => Collection(id: track.collectionId, name: 'Default'),
    );

    final absJsonPath = track.getAbsoluteOutputPath(
      project.directoryPath,
      collection.folderName,
    );
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
