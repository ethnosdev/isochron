import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

enum AlignmentStatus { pending, processing, done, reviewed, error }

/// Represents a single linked pair of Audio and Text inside a Collection.
class Track {
  final String id;
  String name;
  String? audioPath;
  String? textPath;
  final String outputFilename;
  AlignmentStatus status;

  Track({
    required this.id,
    required this.name,
    this.audioPath,
    this.textPath,
    required this.outputFilename,
    this.status = AlignmentStatus.pending,
  });

  String getAbsoluteOutputPath(String projectDir) {
    return p.join(projectDir, 'alignments', outputFilename);
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
    return Track(
      id: json['id'],
      name: json['name'] ?? 'Track',
      audioPath: json['audioPath'],
      textPath: json['textPath'],
      outputFilename: json['outputFilename'],
      status: AlignmentStatus.values[json['status'] ?? 0],
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
    return Collection(
      id: json['id'],
      name: json['name'],
      tracks:
          (json['tracks'] as List?)
              ?.map((i) => Track.fromJson(i as Map<String, dynamic>))
              .toList() ??
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
  };

  factory Project.fromJson(Map<String, dynamic> json) {
    List<Collection> migratedCollections = [];

    // 1. CURRENT FORMAT
    if (json.containsKey('collections')) {
      migratedCollections = (json['collections'] as List)
          .map((i) => Collection.fromJson(i as Map<String, dynamic>))
          .toList();
    }
    // 2. LEGACY FORMATS MIGRATION
    else {
      final defaultCol = Collection(
        id: const Uuid().v4(),
        name: 'Imported Alignments',
      );

      // Legacy v1: Direct Paths under "items" (This matches your pasted JSON)
      if (json.containsKey('items')) {
        for (var item in (json['items'] as List)) {
          defaultCol.tracks.add(
            Track(
              id: item['id'] ?? const Uuid().v4(),
              // Better track naming based on the output filename instead of "Track 1"
              name: p.basenameWithoutExtension(
                item['outputFilename'] ?? 'Track',
              ),
              audioPath: item['audioPath'],
              textPath: item['textPath'],
              outputFilename:
                  item['outputFilename'] ??
                  'alignment_${defaultCol.tracks.length}.json',
              status: AlignmentStatus.values[item['status'] ?? 0],
            ),
          );
        }
      }
      // Legacy v2: Pool IDs under "alignments"
      else if (json.containsKey('alignments')) {
        final audioPool = json['audioPool'] as List? ?? [];
        final textPool = json['textPool'] as List? ?? [];
        final audioMap = {for (var a in audioPool) a['id']: a['path']};
        final textMap = {for (var t in textPool) t['id']: t['path']};

        for (var a in (json['alignments'] as List)) {
          defaultCol.tracks.add(
            Track(
              id: a['id'] ?? const Uuid().v4(),
              name: p.basenameWithoutExtension(a['outputFilename'] ?? 'Track'),
              audioPath: audioMap[a['audioAssetId']],
              textPath: textMap[a['textAssetId']],
              outputFilename: a['outputFilename'],
              status: AlignmentStatus.values[a['status'] ?? 0],
            ),
          );
        }
      }

      if (defaultCol.tracks.isNotEmpty) {
        migratedCollections.add(defaultCol);
      }
    }

    return Project(
      id: json['id'] ?? const Uuid().v4(),
      name: json['name'] ?? 'Project',
      directoryPath: json['directoryPath'],
      collections: migratedCollections,
      // Fallbacks to support various old setting keys
      dictPath:
          json['dictPath'] ?? json['dictionaryPath'] ?? json['dictAssetId'],
      defaultHasIds: json['defaultHasIds'] ?? json['hasIds'] ?? false,
      defaultGenerateIds:
          json['defaultGenerateIds'] ?? json['generateIds'] ?? false,
      defaultIdPrefix: json['defaultIdPrefix'] ?? json['generatedIdPrefix'],
      snapMode: json['snapMode'] ?? 'onset',
      snapOffset: json['snapOffset'],
    );
  }

  Future<void> save() async {
    final file = File(p.join(directoryPath, 'project.json'));
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(toJson()));
  }
}
