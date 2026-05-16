import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

enum AlignmentStatus { pending, processing, done, reviewed, error }

/// Represents a single linked pair of Audio and Text inside a Collection.
class Track {
  final String id;
  String collectionId;
  String name;
  String? audioPath;
  String? textPath;
  final String outputFilename;
  AlignmentStatus status;

  Track({
    required this.id,
    this.collectionId = '',
    required this.name,
    this.audioPath,
    this.textPath,
    required this.outputFilename,
    this.status = AlignmentStatus.pending,
  });

  /// Resolves the absolute path for the output JSON.
  /// Falls back to the legacy root `alignments/` folder if it already exists,
  /// otherwise uses the new `collections/<ID>/alignments/` structure.
  String getAbsoluteOutputPath(String projectDir) {
    final legacyPath = p.join(projectDir, 'alignments', outputFilename);
    final newPath = p.join(
      projectDir,
      'collections',
      collectionId,
      'alignments',
      outputFilename,
    );

    if (File(legacyPath).existsSync() && !File(newPath).existsSync()) {
      return legacyPath;
    }
    return newPath;
  }

  /// Resolves audio path (handles both legacy absolute paths and new relative paths)
  String? getResolvedAudioPath(String projectDir) {
    if (audioPath == null) return null;
    if (p.isAbsolute(audioPath!)) return audioPath;
    return p.join(projectDir, 'collections', collectionId, 'audio', audioPath);
  }

  /// Resolves text path (handles both legacy absolute paths and new relative paths)
  String? getResolvedTextPath(String projectDir) {
    if (textPath == null) return null;
    if (p.isAbsolute(textPath!)) return textPath;
    return p.join(projectDir, 'collections', collectionId, 'text', textPath);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'audioPath': audioPath,
    'textPath': textPath,
    'outputFilename': outputFilename,
    'status': status.index,
  };

  factory Track.fromJson(Map<String, dynamic> json) {
    int statusIdx = json['status'] is int ? json['status'] : 0;
    if (statusIdx < 0 || statusIdx >= AlignmentStatus.values.length)
      statusIdx = 0;

    return Track(
      id: json['id']?.toString() ?? const Uuid().v4(),
      name: json['name']?.toString() ?? 'Track',
      audioPath: json['audioPath']?.toString(),
      textPath: json['textPath']?.toString(),
      outputFilename: json['outputFilename']?.toString() ?? 'alignment.json',
      status: AlignmentStatus.values[statusIdx],
    );
  }
}

/// A grouping of Tracks (e.g. "Gospel of John").
class Collection {
  final String id;
  String name;
  List<Track> tracks;

  Collection({required this.id, required this.name, List<Track>? tracks})
    : tracks = tracks ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'tracks': tracks.map((t) => t.toJson()).toList(),
  };

  factory Collection.fromJson(Map<String, dynamic> json) {
    final colId = json['id']?.toString() ?? const Uuid().v4();
    return Collection(
      id: colId,
      name: json['name']?.toString() ?? 'Collection',
      tracks:
          (json['tracks'] as List?)?.whereType<Map<String, dynamic>>().map((i) {
            final t = Track.fromJson(i);
            t.collectionId = colId;
            return t;
          }).toList() ??
          [],
    );
  }
}

class Project {
  final String id;
  String name;
  final String directoryPath;

  // --- TREE HIERARCHY ---
  List<Collection> collections;

  // --- GLOBAL SETTINGS ---
  String? dictPath;
  bool defaultHasIds;
  bool defaultGenerateIds;
  String? defaultIdPrefix;
  String snapMode;
  int? snapOffset;

  bool copyMediaIntoProject;
  bool hasPromptedForMediaStorage;

  Project({
    required this.id,
    required this.name,
    required this.directoryPath,
    List<Collection>? collections,
    this.dictPath,
    this.defaultHasIds = false,
    this.defaultGenerateIds = false,
    this.defaultIdPrefix,
    this.snapMode = 'onset',
    this.snapOffset,
    this.copyMediaIntoProject = false,
    this.hasPromptedForMediaStorage = false,
  }) : collections = collections ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'directoryPath': directoryPath,
    'collections': collections.map((c) => c.toJson()).toList(),
    'dictPath': dictPath,
    'defaultHasIds': defaultHasIds,
    'defaultGenerateIds': defaultGenerateIds,
    'defaultIdPrefix': defaultIdPrefix,
    'snapMode': snapMode,
    'snapOffset': snapOffset,
    'copyMediaIntoProject': copyMediaIntoProject,
    'hasPromptedForMediaStorage': hasPromptedForMediaStorage,
  };

  factory Project.fromJson(Map<String, dynamic> json) {
    List<Collection> migratedCollections = [];

    // Helper to safely map legacy statuses
    AlignmentStatus parseStatus(dynamic statusVal) {
      int idx = statusVal is int ? statusVal : 0;
      if (idx < 0 || idx >= AlignmentStatus.values.length) {
        idx = 0;
      }
      return AlignmentStatus.values[idx];
    }

    // 1. CURRENT FORMAT
    if (json.containsKey('collections') && json['collections'] is List) {
      migratedCollections = (json['collections'] as List)
          .whereType<Map<String, dynamic>>()
          .map((i) => Collection.fromJson(i))
          .toList();
    }

    // 2. LEGACY FORMATS MIGRATION
    // (Only runs if the project didn't have collections, or the collections array was empty)
    if (migratedCollections.isEmpty) {
      final defaultCol = Collection(
        id: const Uuid().v4(),
        name: 'Imported Alignments',
      );

      // Legacy v1: Direct Paths under "items"
      if (json.containsKey('items') && json['items'] is List) {
        for (var item in (json['items'] as List)) {
          if (item is! Map) continue; // Skip malformed array elements
          defaultCol.tracks.add(
            Track(
              id: item['id']?.toString() ?? const Uuid().v4(),
              // Better track naming based on the output filename instead of "Track 1"
              name: p.basenameWithoutExtension(
                item['outputFilename']?.toString() ?? 'Track',
              ),
              audioPath: item['audioPath']?.toString(),
              textPath: item['textPath']?.toString(),
              outputFilename:
                  item['outputFilename']?.toString() ??
                  'alignment_${defaultCol.tracks.length}.json',
              status: parseStatus(item['status']),
            ),
          );
        }
      }
      // Legacy v2: Pool IDs under "alignments"
      else if (json.containsKey('alignments') && json['alignments'] is List) {
        final audioPool = json['audioPool'] is List
            ? json['audioPool'] as List
            : [];
        final textPool = json['textPool'] is List
            ? json['textPool'] as List
            : [];

        final audioMap = <String, String>{};
        final textMap = <String, String>{};

        for (var a in audioPool) {
          if (a is Map && a['id'] != null && a['path'] != null) {
            audioMap[a['id'].toString()] = a['path'].toString();
          }
        }
        for (var t in textPool) {
          if (t is Map && t['id'] != null && t['path'] != null) {
            textMap[t['id'].toString()] = t['path'].toString();
          }
        }

        for (var a in (json['alignments'] as List)) {
          if (a is! Map) continue;
          defaultCol.tracks.add(
            Track(
              id: a['id']?.toString() ?? const Uuid().v4(),
              name: p.basenameWithoutExtension(
                a['outputFilename']?.toString() ?? 'Track',
              ),
              audioPath: audioMap[a['audioAssetId']?.toString()],
              textPath: textMap[a['textAssetId']?.toString()],
              outputFilename:
                  a['outputFilename']?.toString() ??
                  'alignment_${defaultCol.tracks.length}.json',
              status: parseStatus(a['status']),
            ),
          );
        }
      }

      if (defaultCol.tracks.isNotEmpty) {
        migratedCollections.add(defaultCol);
      }
    }

    return Project(
      id: json['id']?.toString() ?? const Uuid().v4(),
      name: json['name']?.toString() ?? 'Project',
      // Safe fallback ensuring we never pass null to a non-nullable required string
      directoryPath: json['directoryPath']?.toString() ?? '',
      collections: migratedCollections,
      dictPath:
          json['dictPath']?.toString() ??
          json['dictionaryPath']?.toString() ??
          json['dictAssetId']?.toString(),
      defaultHasIds: json['defaultHasIds'] ?? json['hasIds'] ?? false,
      defaultGenerateIds:
          json['defaultGenerateIds'] ?? json['generateIds'] ?? false,
      defaultIdPrefix:
          json['defaultIdPrefix']?.toString() ??
          json['generatedIdPrefix']?.toString(),
      snapMode: json['snapMode']?.toString() ?? 'onset',
      snapOffset: json['snapOffset'] is int ? json['snapOffset'] : null,
      copyMediaIntoProject: json['copyMediaIntoProject'] ?? false,
      hasPromptedForMediaStorage: json['hasPromptedForMediaStorage'] ?? false,
    );
  }

  Future<void> save() async {
    final file = File(p.join(directoryPath, 'project.json'));
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(toJson()));
  }
}
