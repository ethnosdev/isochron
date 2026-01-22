import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

enum ProjectItemStatus { pending, processing, done, error }

class ProjectItem {
  final String id;
  final String audioPath;
  final String textPath;

  /// The filename of the JSON output (stored relative to project dir)
  final String outputFilename;
  final ProjectItemStatus status;

  ProjectItem({
    required this.id,
    required this.audioPath,
    required this.textPath,
    required this.outputFilename,
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
    'status': status.index,
  };

  factory ProjectItem.fromJson(Map<String, dynamic> json) {
    return ProjectItem(
      id: json['id'],
      audioPath: json['audioPath'],
      textPath: json['textPath'],
      outputFilename: json['outputFilename'],
      status: ProjectItemStatus.values[json['status'] ?? 0],
    );
  }

  ProjectItem copyWith({ProjectItemStatus? status}) {
    return ProjectItem(
      id: id,
      audioPath: audioPath,
      textPath: textPath,
      outputFilename: outputFilename,
      status: status ?? this.status,
    );
  }
}

class Project {
  final String id;
  final String name;
  final String directoryPath;
  final String? dictionaryPath;
  final List<ProjectItem> items;

  Project({
    required this.id,
    required this.name,
    required this.directoryPath,
    this.dictionaryPath,
    required this.items,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'directoryPath': directoryPath,
    'dictionaryPath': dictionaryPath,
    'items': items.map((i) => i.toJson()).toList(),
  };

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'],
      name: json['name'],
      directoryPath: json['directoryPath'],
      dictionaryPath: json['dictionaryPath'],
      items: (json['items'] as List)
          .map((i) => ProjectItem.fromJson(i))
          .toList(),
    );
  }

  /// Helper to save the project to disk
  Future<void> save() async {
    final file = File(p.join(directoryPath, 'project.json'));
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(toJson()));
  }
}
