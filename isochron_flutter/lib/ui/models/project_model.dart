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
    // Legacy Migration from Pools & Alignments -> Collections & Tracks
    List<Collection> migratedCollections = [];
    if (json.containsKey('collections')) {
      migratedCollections = (json['collections'] as List)
          .map((i) => Collection.fromJson(i as Map<String, dynamic>))
          .toList();
    } else if (json.containsKey('alignments')) {
      final defaultCol = Collection(
        id: const Uuid().v4(),
        name: 'Imported Alignments',
      );

      final audioPool = json['audioPool'] as List? ?? [];
      final textPool = json['textPool'] as List? ?? [];
      final audioMap = {for (var a in audioPool) a['id']: a['path']};
      final textMap = {for (var t in textPool) t['id']: t['path']};

      for (var a in (json['alignments'] as List)) {
        defaultCol.tracks.add(
          Track(
            id: a['id'],
            name: 'Track ${defaultCol.tracks.length + 1}',
            audioPath: audioMap[a['audioAssetId']],
            textPath: textMap[a['textAssetId']],
            outputFilename: a['outputFilename'],
            status: AlignmentStatus.values[a['status'] ?? 0],
          ),
        );
      }
      migratedCollections.add(defaultCol);
    }

    return Project(
      id: json['id'] ?? const Uuid().v4(),
      name: json['name'] ?? 'Project',
      directoryPath: json['directoryPath'],
      collections: migratedCollections,
      dictPath: json['dictPath'] ?? json['dictAssetId'],
      defaultHasIds: json['defaultHasIds'] ?? false,
      defaultGenerateIds: json['defaultGenerateIds'] ?? false,
      defaultIdPrefix: json['defaultIdPrefix'],
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
