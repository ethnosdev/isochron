import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:isochron_flutter/services/alignment_service.dart';
import 'package:isochron_flutter/services/pins_service.dart';
import 'package:isochron_flutter/ui/workspace/models/workspace_models.dart';
import 'package:isochron_flutter/utils/id_extraction.dart';
import 'package:isochron_flutter/ui/app_manager.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:isochron_cli/isochron_cli.dart';

class ImportResult {
  final int collectionsCount;
  final int tracksCount;
  ImportResult({required this.collectionsCount, required this.tracksCount});
}

class WorkspaceManager extends ChangeNotifier {
  Project? project;
  late final AppManager homeManager;
  final AlignmentService alignmentService = AlignmentService();
  final Uuid uuid = const Uuid();

  bool hasUnsavedChanges = false;

  // Tree State
  TreeSelection? selectedNode;
  final Set<String> expandedNodes = {};
  String? expandedTrackId;
  String? editingNodeId;

  // Batch State
  bool isBatchRunning = false;
  String batchStatus = "";
  double batchProgress = 0.0;

  WorkspaceManager() {
    homeManager = AppManager();
    homeManager.onSaveCallback = () {
      if (selectedNode?.track != null) {
        selectedNode!.track!.status = AlignmentStatus.reviewed;
        project?.save();
        notifyListeners();
      }
    };

    homeManager.onBackgroundAlignmentComplete = (trackId, fragments) {
      if (project != null) {
        for (var col in project!.collections) {
          for (var track in col.tracks) {
            if (track.id == trackId) {
              track.status = AlignmentStatus.done;
              project!.save();
              notifyListeners();
              return;
            }
          }
        }
      }
    };

    homeManager.addListener(() {
      if (homeManager.value.hasUnsavedChanges != hasUnsavedChanges) {
        hasUnsavedChanges = homeManager.value.hasUnsavedChanges;
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    homeManager.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // PROJECT LIFECYCLE
  // ---------------------------------------------------------------------------

  Future<void> createProject(String projectPath, String projectName) async {
    final projectDir = Directory(projectPath);
    await projectDir.create(recursive: true);
    await Directory(p.join(projectDir.path, 'collections')).create();

    final newProject = Project(
      id: uuid.v4(),
      name: projectName,
      directoryPath: projectDir.path,
    );

    final defaultCollection = Collection(
      id: uuid.v4(),
      name: "First Collection",
    );
    newProject.collections.add(defaultCollection);

    await newProject.save();

    project = newProject;
    expandedNodes.add(defaultCollection.id);
    selectedNode = TreeSelection(
      type: NodeType.collection,
      collection: defaultCollection,
    );
    notifyListeners();
  }

  Future<void> openProject(String path) async {
    final content = await File(path).readAsString();
    final parsed = jsonDecode(content);

    project = Project.fromJson(parsed);
    if (project!.collections.isNotEmpty) {
      expandedNodes.add(project!.collections.first.id);
      selectedNode = TreeSelection(
        type: NodeType.collection,
        collection: project!.collections.first,
      );
    }
    notifyListeners();
  }

  void closeProject() {
    project = null;
    selectedNode = null;
    expandedNodes.clear();
    expandedTrackId = null;
    notifyListeners();
  }

  void saveProject() {
    if (selectedNode?.type == NodeType.track) {
      homeManager.saveProject();
    } else {
      project?.save();
    }
  }

  Future<ImportResult> importCollections(String importedFilePath) async {
    if (project == null) {
      return ImportResult(collectionsCount: 0, tracksCount: 0);
    }

    final importedProjectDir = p.dirname(importedFilePath);
    final content = await File(importedFilePath).readAsString();
    final parsed = jsonDecode(content);

    final importedProject = Project.fromJson(parsed);

    List<Collection> newCollections = [];
    int importedTrackCount = 0;

    for (var col in importedProject.collections) {
      final newCol = Collection(id: uuid.v4(), name: col.name);
      final newColDir = Directory(
        p.join(project!.directoryPath, 'collections', newCol.id),
      );

      final alignmentsDir = Directory(p.join(newColDir.path, 'alignments'));
      if (!await alignmentsDir.exists()) {
        await alignmentsDir.create(recursive: true);
      }

      for (var track in col.tracks) {
        File oldJsonFile = File(
          p.join(importedProjectDir, 'alignments', track.outputFilename),
        );
        if (!await oldJsonFile.exists()) {
          oldJsonFile = File(p.join(importedProjectDir, track.outputFilename));
        }

        final safeFilename =
            '${uuid.v4().substring(0, 8)}_${track.outputFilename}';
        final newJsonPath = p.join(alignmentsDir.path, safeFilename);

        if (await oldJsonFile.exists()) {
          await oldJsonFile.copy(newJsonPath);
          final oldPinsFile = File(PinsService.pinsPath(oldJsonFile.path));
          if (await oldPinsFile.exists()) {
            await oldPinsFile.copy(PinsService.pinsPath(newJsonPath));
          }
        }

        String? finalAudio = track.audioPath;
        String? finalText = track.textPath;

        if (project!.copyMediaIntoProject) {
          if (finalAudio != null) {
            final oldAudioFile = File(
              p.isAbsolute(finalAudio)
                  ? finalAudio
                  : p.join(
                      importedProjectDir,
                      'collections',
                      col.id,
                      'audio',
                      finalAudio,
                    ),
            );

            if (await oldAudioFile.exists()) {
              final audioDir = Directory(p.join(newColDir.path, 'audio'));
              if (!await audioDir.exists()) {
                await audioDir.create(recursive: true);
              }
              finalAudio = p.basename(oldAudioFile.path);
              await oldAudioFile.copy(p.join(audioDir.path, finalAudio));
            }
          }

          if (finalText != null) {
            final oldTextFile = File(
              p.isAbsolute(finalText)
                  ? finalText
                  : p.join(
                      importedProjectDir,
                      'collections',
                      col.id,
                      'text',
                      finalText,
                    ),
            );

            if (await oldTextFile.exists()) {
              final textDir = Directory(p.join(newColDir.path, 'text'));
              if (!await textDir.exists()) {
                await textDir.create(recursive: true);
              }
              finalText = p.basename(oldTextFile.path);
              await oldTextFile.copy(p.join(textDir.path, finalText));
            }
          }
        }

        newCol.tracks.add(
          Track(
            id: uuid.v4(),
            collectionId: newCol.id,
            name: track.name,
            audioPath: finalAudio,
            textPath: finalText,
            outputFilename: safeFilename,
            status: track.status,
          ),
        );
        importedTrackCount++;
      }
      newCollections.add(newCol);
    }

    project!.collections.addAll(newCollections);
    for (var c in newCollections) {
      expandedNodes.add(c.id);
    }

    await project!.save();
    notifyListeners();

    return ImportResult(
      collectionsCount: newCollections.length,
      tracksCount: importedTrackCount,
    );
  }

  // ---------------------------------------------------------------------------
  // TREE MODIFICATIONS
  // ---------------------------------------------------------------------------

  void addCollection() {
    if (project == null) return;
    final newCol = Collection(id: uuid.v4(), name: "New Collection");
    project!.collections.add(newCol);
    expandedNodes.add(newCol.id);
    project!.save();
    notifyListeners();
  }

  Future<void> deleteCollection(Collection collection) async {
    project!.collections.remove(collection);
    if (selectedNode?.collection == collection) {
      selectedNode = null;
    }
    expandedNodes.remove(collection.id);
    await project!.save();
    notifyListeners();
  }

  Future<void> deleteTrack(Track track, Collection collection) async {
    final jsonPath = track.getAbsoluteOutputPath(
      project!.directoryPath,
      collection.folderName,
    );
    final pinsPath = PinsService.pinsPath(jsonPath);
    if (await File(jsonPath).exists()) await File(jsonPath).delete();
    if (await File(pinsPath).exists()) await File(pinsPath).delete();

    collection.tracks.remove(track);
    if (selectedNode?.track == track) {
      expandedTrackId = null;
      selectedNode = TreeSelection(
        type: NodeType.collection,
        collection: collection,
      );
    }
    await project!.save();
    notifyListeners();
  }

  Future<void> renameCollection(Collection col, String newName) async {
    final cleanNewName = newName.trim();
    if (cleanNewName.isNotEmpty && cleanNewName != col.name) {
      final oldFolderName = col.folderName;
      final oldPath = p.join(
        project!.directoryPath,
        'collections',
        oldFolderName,
      );

      final dummyCol = Collection(id: col.id, name: cleanNewName);
      final newFolderName = dummyCol.folderName;
      final newPath = p.join(
        project!.directoryPath,
        'collections',
        newFolderName,
      );

      if (Directory(oldPath).existsSync() && !Directory(newPath).existsSync()) {
        try {
          await Directory(oldPath).rename(newPath);
        } catch (e) {
          debugPrint("Failed to rename physical collection folder: $e");
        }
      }

      col.name = cleanNewName;
      await project!.save();
    }
    editingNodeId = null;
    notifyListeners();
  }

  Future<void> renameTrack(Track track, Collection col, String newName) async {
    final cleanNewName = newName.trim();
    if (cleanNewName.isNotEmpty && cleanNewName != track.name) {
      final oldJsonPath = track.getAbsoluteOutputPath(
        project!.directoryPath,
        col.folderName,
      );
      final oldPinsPath = PinsService.pinsPath(oldJsonPath);

      final newFilename = '${cleanNewName}_timing.json';
      track.name = cleanNewName;
      track.outputFilename = newFilename;

      final newJsonPath = track.getAbsoluteOutputPath(
        project!.directoryPath,
        col.folderName,
      );
      final newPinsPath = PinsService.pinsPath(newJsonPath);

      try {
        final alignDir = Directory(p.dirname(newJsonPath));
        if (!await alignDir.exists()) await alignDir.create(recursive: true);

        if (await File(oldJsonPath).exists()) {
          await File(oldJsonPath).rename(newJsonPath);
        }
        if (await File(oldPinsPath).exists()) {
          await File(oldPinsPath).rename(newPinsPath);
        }
      } catch (e) {
        debugPrint("Failed to rename physical files: $e");
      }
      await project!.save();
    }
    editingNodeId = null;
    notifyListeners();
  }

  Future<void> clearAlignmentData(Track track) async {
    final collection = project!.collections.firstWhere(
      (c) => c.id == track.collectionId,
    );
    final jsonPath = track.getAbsoluteOutputPath(
      project!.directoryPath,
      collection.folderName,
    );
    final pinsPath = PinsService.pinsPath(jsonPath);
    if (await File(jsonPath).exists()) await File(jsonPath).delete();
    if (await File(pinsPath).exists()) await File(pinsPath).delete();

    track.status = AlignmentStatus.pending;
    await project!.save();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // BATCH & HEALING
  // ---------------------------------------------------------------------------

  Future<void> runBatch(Collection collection) async {
    if (project == null) return;

    isBatchRunning = true;
    batchStatus = "Starting Batch...";
    batchProgress = 0.0;
    notifyListeners();

    final pendingTracks = collection.tracks
        .where(
          (t) =>
              t.status == AlignmentStatus.pending ||
              t.status == AlignmentStatus.error,
        )
        .toList();

    for (var track in pendingTracks) {
      if (!isBatchRunning) break;

      final resolvedAudio = track.getResolvedAudioPath(
        project!.directoryPath,
        collection.folderName,
      );
      final resolvedText = track.getResolvedTextPath(
        project!.directoryPath,
        collection.folderName,
      );

      if (resolvedAudio == null || resolvedText == null) {
        track.status = AlignmentStatus.error;
        notifyListeners();
        continue;
      }

      track.status = AlignmentStatus.processing;
      batchStatus = "Processing ${track.name}...";
      notifyListeners();

      File? tempCleanTextFile;
      List<String> extractedIds = [];
      String actualTextPath = resolvedText;

      try {
        if (project!.defaultHasIds) {
          final lines = await File(resolvedText).readAsLines();
          final cleanLines = <String>[];
          for (var line in lines) {
            if (line.trim().isEmpty) continue;
            final parsed = extractIdFromLine(line);
            if (parsed.hasId) {
              extractedIds.add(parsed.id);
              cleanLines.add(parsed.content);
            } else {
              extractedIds.add("");
              cleanLines.add(line);
            }
          }
          final tempDir = await getTemporaryDirectory();
          tempCleanTextFile = File(
            p.join(tempDir.path, 'clean_${uuid.v4()}.txt'),
          );
          await tempCleanTextFile.writeAsString(cleanLines.join('\n'));
          actualTextPath = tempCleanTextFile.path;
        }

        List<Fragment> fragments = await alignmentService.runIsochron(
          textPath: actualTextPath,
          audioPath: resolvedAudio,
          dictPath: project!.dictPath,
          snapMode: project!.snapMode,
          snapOffsetMs: project!.snapOffset ?? 0,
          onProgress: (status, prog) {
            if (isBatchRunning) {
              batchStatus = status;
              batchProgress = prog;
              notifyListeners();
            }
          },
        );

        if (!isBatchRunning) {
          track.status = AlignmentStatus.pending;
          notifyListeners();
          break;
        }

        if (project!.defaultHasIds && extractedIds.isNotEmpty) {
          for (int i = 0; i < fragments.length; i++) {
            if (i < extractedIds.length) {
              fragments[i] = fragments[i].copyWith(id: extractedIds[i]);
            }
          }
        }

        if (!project!.defaultHasIds && project!.defaultGenerateIds) {
          final prefix = project!.defaultIdPrefix ?? "";
          int trackIdx = collection.tracks.indexOf(track) + 1;
          final recStr = trackIdx.toString().padLeft(3, '0');
          for (int j = 0; j < fragments.length; j++) {
            final verseStr = (j + 1).toString().padLeft(3, '0');
            fragments[j] = fragments[j].copyWith(id: '$prefix$recStr$verseStr');
          }
        }

        final absPath = track.getAbsoluteOutputPath(
          project!.directoryPath,
          collection.folderName,
        );
        final alignDir = Directory(p.dirname(absPath));
        if (!await alignDir.exists()) await alignDir.create(recursive: true);

        final List<Map<String, dynamic>> jsonList = fragments
            .map(
              (f) => {
                'index': f.index,
                if (f.id != null) 'id': f.id,
                'text': f.text,
                'start': double.parse(f.realStart.toStringAsFixed(3)),
                'end': double.parse(f.realEnd.toStringAsFixed(3)),
              },
            )
            .toList();

        await File(
          absPath,
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(jsonList));
        track.status = AlignmentStatus.done;
      } catch (e) {
        if (!isBatchRunning) {
          track.status = AlignmentStatus.pending;
          break;
        } else {
          track.status = AlignmentStatus.error;
        }
      } finally {
        if (tempCleanTextFile != null && await tempCleanTextFile.exists()) {
          await tempCleanTextFile.delete();
        }
      }

      await project!.save();
      notifyListeners();
    }

    isBatchRunning = false;
    batchStatus = "Batch Complete";
    batchProgress = 1.0;
    notifyListeners();
  }

  void stopBatch() {
    isBatchRunning = false;
    alignmentService.cancelCurrentRun();
    notifyListeners();
  }

  Future<int> healBrokenLinks(
    Collection collection,
    String selectedFolder,
  ) async {
    final dir = Directory(selectedFolder);
    final Map<String, String> fileMap = {};

    try {
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          fileMap[p.basename(entity.path)] = entity.path;
        }
      }
    } catch (e) {
      debugPrint("Error scanning directory: $e");
      return 0;
    }

    int healedCount = 0;
    for (var track in collection.tracks) {
      if (track.audioPath != null) {
        final resolvedPath = track.getResolvedAudioPath(
          project!.directoryPath,
          collection.folderName,
        )!;
        if (!File(resolvedPath).existsSync() &&
            fileMap.containsKey(p.basename(resolvedPath))) {
          track.audioPath = fileMap[p.basename(resolvedPath)]!;
          healedCount++;
        }
      }
      if (track.textPath != null) {
        final resolvedPath = track.getResolvedTextPath(
          project!.directoryPath,
          collection.folderName,
        )!;
        if (!File(resolvedPath).existsSync() &&
            fileMap.containsKey(p.basename(resolvedPath))) {
          track.textPath = fileMap[p.basename(resolvedPath)]!;
          healedCount++;
        }
      }
    }

    if (healedCount > 0) {
      await project!.save();
      notifyListeners();
    }
    return healedCount;
  }

  // ---------------------------------------------------------------------------
  // UI SELECTION & STATE HELPERS
  // ---------------------------------------------------------------------------

  void setEditingNode(String? id) {
    editingNodeId = id;
    notifyListeners();
  }

  void toggleExpandedNode(String id) {
    if (expandedNodes.contains(id)) {
      expandedNodes.remove(id);
    } else {
      expandedNodes.add(id);
    }
    notifyListeners();
  }

  void selectNode(TreeSelection selection) {
    selectedNode = selection;
    if (selection.type == NodeType.track && selection.track != null) {
      expandedTrackId = selection.track!.id;
    } else if (selection.type == NodeType.collection) {
      expandedNodes.add(selection.collection!.id);
    }
    notifyListeners();
  }

  void setExpandedTrack(String? trackId) {
    expandedTrackId = trackId;
    notifyListeners();
  }

  void loadTrackInEditor(Track track) {
    homeManager.value = homeManager.value.copyWith(
      clearWaveform: true,
      clearFocus: true,
      fragments: [],
      statusMessage: "Loading...",
    );
    Future.delayed(const Duration(milliseconds: 50), () {
      homeManager.loadTrack(track, project!);
    });
  }

  void refreshUi() {
    notifyListeners();
  }
}
