import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

enum ProjectItemStatus { pending, processing, done, reviewed, error }

class ProjectItem {
  final String id;
  final String audioPath;
  final String textPath;
  final bool hasIds; // Kept for legacy compatibility at the item level

  /// The filename of the JSON output (stored relative to project dir)
  final String outputFilename;
  final ProjectItemStatus status;

  ProjectItem({
    required this.id,
    required this.audioPath,
    required this.textPath,
    required this.outputFilename,
    required this.hasIds,
    this.status = ProjectItemStatus.pending,
  });

  /// Helper to get the full absolute path of the output JSON
  String getAbsoluteOutputPath(String projectDir) {
    return p.join(projectDir, 'alignments', outputFilename);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'audioPath': audioPath,
    'textPath': textPath,
    'outputFilename': outputFilename,
    'hasIds': hasIds,
    'status': status.index,
  };

  factory ProjectItem.fromJson(Map<String, dynamic> json) {
    return ProjectItem(
      id: json['id'],
      audioPath: json['audioPath'],
      textPath: json['textPath'],
      outputFilename: json['outputFilename'],
      hasIds: json['hasIds'] ?? false,
      status: ProjectItemStatus.values[json['status'] ?? 0],
    );
  }

  ProjectItem copyWith({ProjectItemStatus? status}) {
    return ProjectItem(
      id: id,
      audioPath: audioPath,
      textPath: textPath,
      outputFilename: outputFilename,
      hasIds: hasIds,
      status: status ?? this.status,
    );
  }
}

class Project {
  final String id;
  String name;
  final String directoryPath;
  String? dictionaryPath;

  // ID Strategies
  bool hasIds;
  bool generateIds;
  String? generatedIdPrefix;

  /// Controls how fragment boundaries are refined during alignment.
  ///
  /// Stored as string to keep project files stable even if enum implementation
  /// changes. Expected values: 'onset', 'gap'.
  String snapMode;

  final List<ProjectItem> items;

  Project({
    required this.id,
    required this.name,
    required this.directoryPath,
    this.dictionaryPath,
    required this.hasIds,
    this.generateIds = false,
    this.generatedIdPrefix,
    this.snapMode = 'onset',
    required this.items,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'directoryPath': directoryPath,
    'dictionaryPath': dictionaryPath,
    'hasIds': hasIds,
    'generateIds': generateIds,
    'generatedIdPrefix': generatedIdPrefix,
    'snapMode': snapMode,
    'items': items.map((i) => i.toJson()).toList(),
  };

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'],
      name: json['name'],
      directoryPath: json['directoryPath'],
      dictionaryPath: json['dictionaryPath'],
      hasIds: json['hasIds'] ?? false,
      generateIds: json['generateIds'] ?? false,
      generatedIdPrefix: json['generatedIdPrefix'],
      snapMode: json['snapMode'] ?? 'onset',
      items: (json['items'] as List)
          .map((i) => ProjectItem.fromJson(i))
          .toList(),
    );
  }

  /// Saves the project metadata to [directoryPath]/project.json
  Future<void> save() async {
    final file = File(p.join(directoryPath, 'project.json'));
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(toJson()));
  }
}
