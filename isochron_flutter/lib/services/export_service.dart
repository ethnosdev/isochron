import 'dart:convert';
import 'dart:io';

import 'package:isochron_cli/isochron_cli.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:path/path.dart' as p;

enum GroupExportMode {
  separateFiles,
  singleFile,
}

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

  /// Builds a single-chapter phrase-timing payload combining all exportable tracks.
  /// All phrases are included under a single `\c <chapterId>` header, with each
  /// track's timings restarting from 0.0 seconds.
  static Future<String?> buildSingleChapterPayload(
    Project project,
    List<Track> tracks, {
    String? bookCode,
    String chapterId = '1',
    bool? requireIds,
  }) async {
    final exportableTracks = tracks.where(canExportPhraseTiming).toList();
    if (exportableTracks.isEmpty) return null;

    final effectiveRequireIds = requireIds ??
        (project.defaultHasIds || project.defaultGenerateIds);

    String effectiveBookCode = bookCode?.trim() ?? '';
    if (effectiveBookCode.isEmpty) {
      for (final track in exportableTracks) {
        final meta = parsePhraseMetadataFromTextFilename(track.textPath);
        if (meta.bookCode != TimingExportMetadata.fallback.bookCode) {
          effectiveBookCode = meta.bookCode;
          break;
        }
      }
    }
    if (effectiveBookCode.isEmpty) {
      effectiveBookCode = 'BOOK';
    }

    final buffer = StringBuffer();
    buffer.writeln('\\id $effectiveBookCode');
    buffer.writeln('\\c $chapterId');
    buffer.writeln('\\level phrase');

    for (final track in exportableTracks) {
      final entries = await _loadAlignmentEntries(project, track);
      final fragments = _entriesToFragments(entries);
      if (fragments.isEmpty) continue;

      if (effectiveRequireIds) {
        final missing = fragments.where(
          (f) => f.id == null || f.id!.trim().isEmpty,
        );
        if (missing.isNotEmpty) {
          throw MissingPhraseIdException(
            'Missing phrase ID in track "${track.name}". Export aborted — enable "Has IDs" or verify source file ID formatting.',
          );
        }
      }

      for (int i = 0; i < fragments.length; i++) {
        final f = fragments[i];
        final phraseId = (f.id != null && f.id!.trim().isNotEmpty)
            ? f.id!.trim()
            : '${i + 1}';
        final start = TimingExport.formatSeconds(f.realStart);
        final end = TimingExport.formatSeconds(f.realEnd);
        buffer.writeln('$start\t$end\t$phraseId');
      }
    }

    return buffer.toString();
  }

  /// Builds a single phrase-timing payload with multiple chapter sections,
  /// dividing each track into its own `\c <chapterId>` section.
  static Future<String?> buildDividedChaptersSingleFilePayload(
    Project project,
    List<Track> tracks, {
    bool? requireIds,
  }) async {
    final exportableTracks = tracks.where(canExportPhraseTiming).toList();
    if (exportableTracks.isEmpty) return null;

    final buffer = StringBuffer();
    for (final track in exportableTracks) {
      final payload = await buildPhraseTiming(
        project,
        track,
        requireIds: requireIds,
      );
      if (payload != null && payload.isNotEmpty) {
        buffer.write(payload);
        if (!payload.endsWith('\n')) buffer.writeln();
      }
    }

    return buffer.toString();
  }

  /// Exports each track as its own `.txt` file into [destinationDir]
  /// (or [destinationDir]/[subfolderName] if specified).
  static Future<int> exportDividedChaptersToDirectory(
    Project project,
    List<Track> tracks,
    String destinationDir, {
    bool? requireIds,
    String? subfolderName,
  }) async {
    final exportableTracks = tracks.where(canExportPhraseTiming).toList();
    if (exportableTracks.isEmpty) return 0;

    final targetDir = (subfolderName != null && subfolderName.isNotEmpty)
        ? Directory(p.join(destinationDir, subfolderName))
        : Directory(destinationDir);

    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final usedFilenames = <String>{};
    int count = 0;

    for (final track in exportableTracks) {
      final payload = await buildPhraseTiming(
        project,
        track,
        requireIds: requireIds,
      );
      if (payload != null) {
        final baseName = defaultPhraseTimingFilenameForTrack(track);
        final filename = resolveUniqueFilename(usedFilenames, baseName);
        final file = File(p.join(targetDir.path, filename));
        await file.writeAsString(payload);
        count++;
      }
    }

    return count;
  }

  /// Exports an entire project's tracks divided by chapter into [destinationDir].
  /// If the project contains multiple collections, each collection is placed in its
  /// own subfolder.
  static Future<int> exportProjectDividedChaptersToDirectory(
    Project project,
    String destinationDir, {
    bool? requireIds,
  }) async {
    int totalCount = 0;
    final collections = project.collections;
    final multiCollections = collections.length > 1;

    for (final col in collections) {
      final subfolder = multiCollections ? col.folderName : null;
      final count = await exportDividedChaptersToDirectory(
        project,
        col.tracks,
        destinationDir,
        requireIds: requireIds,
        subfolderName: subfolder,
      );
      totalCount += count;
    }

    return totalCount;
  }

  /// Resolves filename collisions in folder exports by appending an incrementing index.
  static String resolveUniqueFilename(Set<String> used, String filename) {
    if (!used.contains(filename)) {
      used.add(filename);
      return filename;
    }
    final nameWithoutExt = p.basenameWithoutExtension(filename);
    final ext = p.extension(filename);
    int counter = 2;
    while (used.contains('$nameWithoutExt ($counter)$ext')) {
      counter++;
    }
    final unique = '$nameWithoutExt ($counter)$ext';
    used.add(unique);
    return unique;
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
