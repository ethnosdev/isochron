import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

enum AlignmentStatus { pending, processing, done, reviewed, error }

/// Represents a raw file living in one of the project's pools.
class ProjectAsset {
  final String id;
  final String path;

  ProjectAsset({required this.id, required this.path});

  String get filename => p.basename(path);

  Map<String, dynamic> toJson() => {'id': id, 'path': path};

  factory ProjectAsset.fromJson(Map<String, dynamic> json) {
    return ProjectAsset(id: json['id'], path: json['path']);
  }
}

/// Represents the relationship linking an Audio file, a Text file, and a Dictionary.
class AlignmentPair {
  final String id;
  String? audioAssetId;
  String? textAssetId;
  String? dictAssetId;
  final String outputFilename;
  AlignmentStatus status;

  // Local overrides
  bool? overrideHasIds;

  AlignmentPair({
    required this.id,
    this.audioAssetId,
    this.textAssetId,
    this.dictAssetId,
    required this.outputFilename,
    this.status = AlignmentStatus.pending,
    this.overrideHasIds,
  });

  String getAbsoluteOutputPath(String projectDir) {
    return p.join(projectDir, 'alignments', outputFilename);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'audioAssetId': audioAssetId,
    'textAssetId': textAssetId,
    'dictAssetId': dictAssetId,
    'outputFilename': outputFilename,
    'status': status.index,
    'overrideHasIds': overrideHasIds,
  };

  factory AlignmentPair.fromJson(Map<String, dynamic> json) {
    return AlignmentPair(
      id: json['id'],
      audioAssetId: json['audioAssetId'],
      textAssetId: json['textAssetId'],
      dictAssetId: json['dictAssetId'],
      outputFilename: json['outputFilename'],
      status: AlignmentStatus.values[json['status'] ?? 0],
      overrideHasIds: json['overrideHasIds'],
    );
  }
}

class Project {
  final String id;
  String name;
  final String directoryPath;

  // --- ASSET POOLS ---
  List<ProjectAsset> audioPool;
  List<ProjectAsset> textPool;
  List<ProjectAsset> dictPool;

  // --- ALIGNMENTS ---
  List<AlignmentPair> alignments;

  // --- GLOBAL SETTINGS ---
  bool defaultHasIds;
  bool defaultGenerateIds;
  String? defaultIdPrefix;
  String snapMode;
  int? snapOffset;

  Project({
    required this.id,
    required this.name,
    required this.directoryPath,
    List<ProjectAsset>? audioPool,
    List<ProjectAsset>? textPool,
    List<ProjectAsset>? dictPool,
    List<AlignmentPair>? alignments,
    this.defaultHasIds = false,
    this.defaultGenerateIds = false,
    this.defaultIdPrefix,
    this.snapMode = 'onset',
    this.snapOffset,
  }) : audioPool = audioPool ?? [],
       textPool = textPool ?? [],
       dictPool = dictPool ?? [],
       alignments = alignments ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'directoryPath': directoryPath,
    'audioPool': audioPool.map((a) => a.toJson()).toList(),
    'textPool': textPool.map((a) => a.toJson()).toList(),
    'dictPool': dictPool.map((a) => a.toJson()).toList(),
    'alignments': alignments.map((a) => a.toJson()).toList(),
    'defaultHasIds': defaultHasIds,
    'defaultGenerateIds': defaultGenerateIds,
    'defaultIdPrefix': defaultIdPrefix,
    'snapMode': snapMode,
    'snapOffset': snapOffset,
  };

  factory Project.fromJson(Map<String, dynamic> json) {
    // -------------------------------------------------------------------------
    // LEGACY MIGRATION: Upgrades old v1 projects automatically on open
    // -------------------------------------------------------------------------
    if (json.containsKey('items')) {
      return _migrateLegacyProject(json);
    }

    // -------------------------------------------------------------------------
    // NEW PARSER
    // -------------------------------------------------------------------------
    return Project(
      id: json['id'],
      name: json['name'],
      directoryPath: json['directoryPath'],
      audioPool:
          (json['audioPool'] as List?)
              ?.map((i) => ProjectAsset.fromJson(i as Map<String, dynamic>))
              .toList() ??
          [],
      textPool:
          (json['textPool'] as List?)
              ?.map((i) => ProjectAsset.fromJson(i as Map<String, dynamic>))
              .toList() ??
          [],
      dictPool:
          (json['dictPool'] as List?)
              ?.map((i) => ProjectAsset.fromJson(i as Map<String, dynamic>))
              .toList() ??
          [],
      alignments:
          (json['alignments'] as List?)
              ?.map((i) => AlignmentPair.fromJson(i as Map<String, dynamic>))
              .toList() ??
          [],
      defaultHasIds: json['defaultHasIds'] ?? false,
      defaultGenerateIds: json['defaultGenerateIds'] ?? false,
      defaultIdPrefix: json['defaultIdPrefix'],
      snapMode: json['snapMode'] ?? 'onset',
      snapOffset: json['snapOffset'],
    );
  }

  static Project _migrateLegacyProject(Map<String, dynamic> json) {
    final audioPool = <ProjectAsset>[];
    final textPool = <ProjectAsset>[];
    final dictPool = <ProjectAsset>[];
    final alignments = <AlignmentPair>[];
    const uuid = Uuid();

    // 1. Migrate Dictionary
    String? dictAssetId;
    if (json['dictionaryPath'] != null) {
      dictAssetId = uuid.v4();
      dictPool.add(ProjectAsset(id: dictAssetId, path: json['dictionaryPath']));
    }

    // 2. Iterate old items and populate pools and pairings
    final items = json['items'] as List? ?? [];
    for (var item in items) {
      // Find or create Audio Asset
      String? audioId;
      if (item['audioPath'] != null) {
        final existing = audioPool
            .where((a) => a.path == item['audioPath'])
            .firstOrNull;
        if (existing != null) {
          audioId = existing.id;
        } else {
          audioId = uuid.v4();
          audioPool.add(ProjectAsset(id: audioId, path: item['audioPath']));
        }
      }

      // Find or create Text Asset
      String? textId;
      if (item['textPath'] != null) {
        final existing = textPool
            .where((a) => a.path == item['textPath'])
            .firstOrNull;
        if (existing != null) {
          textId = existing.id;
        } else {
          textId = uuid.v4();
          textPool.add(ProjectAsset(id: textId, path: item['textPath']));
        }
      }

      // Create Alignment Link
      alignments.add(
        AlignmentPair(
          id: item['id'] ?? uuid.v4(),
          audioAssetId: audioId,
          textAssetId: textId,
          dictAssetId: dictAssetId,
          outputFilename:
              item['outputFilename'] ??
              'alignment_${uuid.v4().substring(0, 4)}.json',
          status: AlignmentStatus.values[item['status'] ?? 0],
          overrideHasIds: item['hasIds'],
        ),
      );
    }

    return Project(
      id: json['id'] ?? uuid.v4(),
      name: json['name'] ?? 'Legacy Project',
      directoryPath: json['directoryPath'] ?? '',
      audioPool: audioPool,
      textPool: textPool,
      dictPool: dictPool,
      alignments: alignments,
      defaultHasIds: json['hasIds'] ?? false,
      defaultGenerateIds: json['generateIds'] ?? false,
      defaultIdPrefix: json['generatedIdPrefix'],
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
