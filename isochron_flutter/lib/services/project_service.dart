import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class ProjectService {
  final _uuid = const Uuid();

  Future<Project?> createNewProject(
    String name,
    List<String> audioPaths,
    List<String> textPaths,
    String? dictPath,
    bool hasIds,
    bool generateIds,
    String? generatedIdPrefix,
  ) async {
    final settings = UserSettingsService();

    String? selectedDirectory = await FilePicker.getDirectoryPath(
      dialogTitle: "Select Folder to Save Project",
      initialDirectory: settings.lastProjectDir,
    );

    if (selectedDirectory == null) return null;
    await settings.setLastProjectDir(selectedDirectory);

    final projectDir = Directory(p.join(selectedDirectory, name));
    if (!await projectDir.exists()) await projectDir.create();

    final alignmentDir = Directory(p.join(projectDir.path, 'alignments'));
    if (!await alignmentDir.exists()) await alignmentDir.create();

    final items = _pairFiles(audioPaths, textPaths, hasIds);

    final project = Project(
      id: _uuid.v4(),
      name: name,
      directoryPath: projectDir.path,
      dictionaryPath: dictPath,
      items: items,
      hasIds: hasIds,
      generateIds: generateIds,
      generatedIdPrefix: generatedIdPrefix,
      snapMode: 'onset',
    );

    await project.save();
    return project;
  }

  Future<Project> loadProject(String jsonPath) async {
    final file = File(jsonPath);
    final content = await file.readAsString();
    return Project.fromJson(jsonDecode(content));
  }

  List<ProjectItem> _pairFiles(
    List<String> audio,
    List<String> text,
    bool hasIds,
  ) {
    audio.sort((a, b) => p.basename(a).compareTo(p.basename(b)));
    text.sort((a, b) => p.basename(a).compareTo(p.basename(b)));

    final List<ProjectItem> items = [];
    final int count = audio.length > text.length ? audio.length : text.length;

    for (int i = 0; i < count; i++) {
      if (i < audio.length && i < text.length) {
        final name = p.basenameWithoutExtension(audio[i]);
        items.add(
          ProjectItem(
            id: _uuid.v4(),
            audioPath: audio[i],
            textPath: text[i],
            outputFilename: '$name.json',
            hasIds: hasIds,
          ),
        );
      }
    }
    return items;
  }
}
