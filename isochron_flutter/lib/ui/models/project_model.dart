import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

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

  // Local overrides (allows one file to use a different strategy than the rest of the project)
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

  /// Helper to get the full absolute path of the output JSON
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
    this.audioPool = const [],
    this.textPool = const [],
    this.dictPool = const [],
    this.alignments = const [],
    this.defaultHasIds = false,
    this.defaultGenerateIds = false,
    this.defaultIdPrefix,
    this.snapMode = 'onset',
    this.snapOffset,
  });

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
    return Project(
      id: json['id'],
      name: json['name'],
      directoryPath: json['directoryPath'],
      audioPool:
          (json['audioPool'] as List?)
              ?.map((i) => ProjectAsset.fromJson(i))
              .toList() ??
          [],
      textPool:
          (json['textPool'] as List?)
              ?.map((i) => ProjectAsset.fromJson(i))
              .toList() ??
          [],
      dictPool:
          (json['dictPool'] as List?)
              ?.map((i) => ProjectAsset.fromJson(i))
              .toList() ??
          [],
      alignments:
          (json['alignments'] as List?)
              ?.map((i) => AlignmentPair.fromJson(i))
              .toList() ??
          [],
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
