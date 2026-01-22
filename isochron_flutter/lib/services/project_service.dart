import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class ProjectService {
  final _uuid = const Uuid();

  /// Prompts user to pick a folder, then initializes the project structure.
  Future<Project?> createNewProject(
    String name,
    List<String> audioPaths,
    List<String> textPaths,
    String? dictPath,
    bool hasIds,
  ) async {
    final settings = UserSettingsService();

    // 1. Pick Directory
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: "Select Folder to Save Project",
    );

    if (selectedDirectory == null) return null;

    await settings.setLastProjectDir(selectedDirectory);

    final projectDir = Directory(p.join(selectedDirectory, name));
    if (!await projectDir.exists()) {
      await projectDir.create();
    }

    // 2. Create 'alignments' subfolder
    final alignmentDir = Directory(p.join(projectDir.path, 'alignments'));
    if (!await alignmentDir.exists()) {
      await alignmentDir.create();
    }

    // 3. Create Items (The Pairing Logic)
    final items = _pairFiles(audioPaths, textPaths, hasIds);

    // 4. Create Project Object
    final project = Project(
      id: _uuid.v4(),
      name: name,
      directoryPath: projectDir.path,
      dictionaryPath: dictPath,
      items: items,
      hasIds: hasIds,
    );

    // 5. Save to JSON
    await project.save();

    return project;
  }

  Future<Project> loadProject(String jsonPath) async {
    final file = File(jsonPath);
    final content = await file.readAsString();
    // We assume the directory is the parent of the json file
    // This allows moving the project folder (as long as absolute paths inside valid)
    // Note: Since we used Option A (Absolute paths for audio), moving audio breaks it.
    // But moving the project folder itself is fine.
    return Project.fromJson(jsonDecode(content));
  }

  /// Auto-pairs files based on sorting.
  /// This is the "Data Logic" for the wizard.
  List<ProjectItem> _pairFiles(
    List<String> audio,
    List<String> text,
    bool hasIds,
  ) {
    // Sort to increase chance of matching
    audio.sort((a, b) => p.basename(a).compareTo(p.basename(b)));
    text.sort((a, b) => p.basename(a).compareTo(p.basename(b)));

    final List<ProjectItem> items = [];
    final int count = audio.length > text.length ? audio.length : text.length;

    for (int i = 0; i < count; i++) {
      // If we run out of text files, we might have an orphan audio
      // In a real app, you might handle 'null' text paths,
      // but for simplicity we assume the UI enforces alignment or we ignore orphans.
      if (i < audio.length && i < text.length) {
        final audioPath = audio[i];
        final textPath = text[i];
        final name = p.basenameWithoutExtension(audioPath);

        items.add(
          ProjectItem(
            id: _uuid.v4(),
            audioPath: audioPath,
            textPath: textPath,
            outputFilename: '$name.json',
            hasIds: hasIds,
            status: ProjectItemStatus.pending,
          ),
        );
      }
    }
    return items;
  }
}
