import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:isochron_cli/isochron_cli.dart';
import 'package:isochron_flutter/services/alignment_service.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'package:isochron_flutter/ui/app_manager.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:isochron_flutter/ui/workspace/models/workspace_models.dart';
import 'package:isochron_flutter/utils/id_extraction.dart';
import 'package:isochron_flutter/utils/natural_sort.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../../utils/file_sync_tracker.dart';

class ImportResult {
  final int collectionsCount;
  final int tracksCount;
  ImportResult({required this.collectionsCount, required this.tracksCount});
}

class WorkspaceManager extends ChangeNotifier {
  Project? project;
  late final AppManager homeManager;
  final AlignmentService alignmentService;
  final Uuid uuid = const Uuid();

  bool hasUnsavedChanges = false;

  // Tree State
  TreeSelection? selectedNode;
  final Set<String> expandedNodes = {};
  String? editingNodeId;

  // Batch State
  bool isBatchRunning = false;
  String batchStatus = "";
  double batchProgress = 0.0;

  // Background Sync Watcher
  StreamSubscription<FileSystemEvent>? _watcherSubscription;
  Timer? _watcherDebounceTimer;
  final Set<String> _pendingChangedPaths = {};

  @visibleForTesting
  Duration watcherDebounceDuration = const Duration(milliseconds: 300);

  @visibleForTesting
  bool get isWatcherActive => _watcherSubscription != null;

  WorkspaceManager({
    AppManager? customHomeManager,
    AlignmentService? customAlignmentService,
  })  : homeManager = customHomeManager ?? AppManager(),
        alignmentService = customAlignmentService ?? AlignmentService() {
    homeManager.onSaveCallback = () {
      if (selectedNode?.track != null && project != null) {
        final track = selectedNode!.track!;
        final frags = homeManager.value.fragments;
        final hasEdits = frags.any(
          (f) =>
              f.status == FragmentStatus.edited ||
              f.status == FragmentStatus.reviewed,
        );
        if (hasEdits) {
          track.status = AlignmentStatus.reviewed;
        } else if (frags.isNotEmpty && frags.any((f) => f.realStart >= 0)) {
          track.status = AlignmentStatus.done;
        }
        final col = project!.collections.firstWhere(
          (c) => c.id == track.collectionId,
          orElse: () => project!.collections.first,
        );
        col.saveTracks(project!.directoryPath);
        notifyListeners();
      }
    };

    homeManager.onBackgroundAlignmentComplete = (trackId, fragments) {
      if (project != null) {
        for (var col in project!.collections) {
          for (var track in col.tracks) {
            if (track.id == trackId) {
              track.status = AlignmentStatus.done;
              col.saveTracks(project!.directoryPath);
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
    _stopDirectoryWatcher();
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
    _startDirectoryWatcher();
    notifyListeners();
  }

  Future<void> openProject(String path) async {
    final content = await File(path).readAsString();
    final parsed = jsonDecode(content) as Map<String, dynamic>;
    parsed['directoryPath'] = p.dirname(path);

    project = Project.fromJson(parsed);
    if (project!.collections.isNotEmpty) {
      expandedNodes.add(project!.collections.first.id);
      selectedNode = TreeSelection(
        type: NodeType.collection,
        collection: project!.collections.first,
      );
    }
    _startDirectoryWatcher();
    notifyListeners();
  }

  void closeProject() {
    _stopDirectoryWatcher();
    project = null;
    selectedNode = null;
    expandedNodes.clear();
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
    final parsed = jsonDecode(content) as Map<String, dynamic>;
    parsed['directoryPath'] = importedProjectDir;

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
    selectNode(TreeSelection(type: NodeType.collection, collection: newCol));
    editingNodeId = newCol.id;
    notifyListeners();
  }

  Future<void> importFilesIntoCollection(Collection col) async {
    if (project == null) return;
    final settings = UserSettingsService();
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      initialDirectory: settings.lastSourceDir,
    );
    if (result == null || result.files.isEmpty) return;

    String? firstValidPath;
    for (final f in result.files) {
      if (f.path != null) {
        firstValidPath = f.path;
        break;
      }
    }
    if (firstValidPath != null) {
      settings.setLastSourceDir(p.dirname(firstValidPath));
    }

    final audioFiles = <String>[];
    final textFiles = <String>[];
    for (final f in result.files) {
      if (f.path == null) continue;
      final ext = p.extension(f.path!).toLowerCase();
      if (['.mp3', '.wav', '.m4a'].contains(ext)) {
        audioFiles.add(f.path!);
      } else if (['.txt', '.phrases'].contains(ext)) {
        textFiles.add(f.path!);
      }
    }

    naturalSort(audioFiles);
    naturalSort(textFiles);

    final maxCount = math.max(audioFiles.length, textFiles.length);
    final projectDir = project!.directoryPath;
    final copyMedia = project!.copyMediaIntoProject;

    for (int i = 0; i < maxCount; i++) {
      final audio = i < audioFiles.length ? audioFiles[i] : null;
      final text = i < textFiles.length ? textFiles[i] : null;
      final trackName = audio != null
          ? p.basenameWithoutExtension(audio)
          : p.basenameWithoutExtension(text!);

      String? finalAudio = audio;
      String? finalText = text;

      if (copyMedia) {
        if (audio != null) {
          final audioDir = Directory(
            p.join(projectDir, 'collections', col.folderName, 'audio'),
          );
          if (!await audioDir.exists()) await audioDir.create(recursive: true);
          final dest = p.join(audioDir.path, p.basename(audio));
          await File(audio).copy(dest);
          finalAudio = p.basename(audio);
        }
        if (text != null) {
          final textDir = Directory(
            p.join(projectDir, 'collections', col.folderName, 'text'),
          );
          if (!await textDir.exists()) await textDir.create(recursive: true);
          final dest = p.join(textDir.path, p.basename(text));
          await File(text).copy(dest);
          finalText = p.basename(text);
        }
      }

      final track = Track(
        id: uuid.v4(),
        collectionId: col.id,
        name: trackName,
        audioPath: finalAudio,
        textPath: finalText,
        outputFilename: '${trackName}_timing.json',
        status: AlignmentStatus.pending,
      );
      col.tracks.add(track);
    }

    await col.saveTracks(projectDir);
    await project!.save();
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
    if (await File(jsonPath).exists()) await File(jsonPath).delete();

    collection.tracks.remove(track);
    if (selectedNode?.track == track) {
      selectedNode = TreeSelection(
        type: NodeType.collection,
        collection: collection,
      );
    }
    await collection.saveTracks(project!.directoryPath);
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

      final newFilename = '${cleanNewName}_timing.json';
      track.name = cleanNewName;
      track.outputFilename = newFilename;

      final newJsonPath = track.getAbsoluteOutputPath(
        project!.directoryPath,
        col.folderName,
      );

      try {
        final alignDir = Directory(p.dirname(newJsonPath));
        if (!await alignDir.exists()) await alignDir.create(recursive: true);

        if (await File(oldJsonPath).exists()) {
          await File(oldJsonPath).rename(newJsonPath);
        }
      } catch (e) {
        debugPrint("Failed to rename physical files: $e");
      }
      await col.saveTracks(project!.directoryPath);
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
    if (await File(jsonPath).exists()) await File(jsonPath).delete();

    track.status = AlignmentStatus.pending;
    await collection.saveTracks(project!.directoryPath);
    notifyListeners();
  }

  Future<void> replaceTrackAudio(Track track, Collection col, String newSourcePath) async {
    if (project == null) return;
    if (project!.copyMediaIntoProject) {
      final audioDir = Directory(
        p.join(
          project!.directoryPath,
          'collections',
          col.folderName,
          'audio',
        ),
      );
      if (!await audioDir.exists()) await audioDir.create(recursive: true);
      final newPath = p.join(audioDir.path, p.basename(newSourcePath));
      await File(newSourcePath).copy(newPath);
      track.audioPath = p.basename(newSourcePath);
    } else {
      track.audioPath = newSourcePath;
    }
    await clearAlignmentData(track);
    await col.saveTracks(project!.directoryPath);
    if (selectedNode?.track?.id == track.id) {
      loadTrackInEditor(track);
    }
    notifyListeners();
  }

  Future<void> replaceTrackText(Track track, Collection col, String newSourcePath) async {
    if (project == null) return;
    if (project!.copyMediaIntoProject) {
      final textDir = Directory(
        p.join(
          project!.directoryPath,
          'collections',
          col.folderName,
          'text',
        ),
      );
      if (!await textDir.exists()) await textDir.create(recursive: true);
      final newPath = p.join(textDir.path, p.basename(newSourcePath));
      await File(newSourcePath).copy(newPath);
      track.textPath = p.basename(newSourcePath);
    } else {
      track.textPath = newSourcePath;
    }
    await clearAlignmentData(track);
    await col.saveTracks(project!.directoryPath);
    if (selectedNode?.track?.id == track.id) {
      loadTrackInEditor(track);
    }
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

      final canonicalTrack = collection.tracks.firstWhere(
        (t) => t.id == track.id,
        orElse: () => track,
      );

      final resolvedAudio = canonicalTrack.getResolvedAudioPath(
        project!.directoryPath,
        collection.folderName,
      );
      final resolvedText = canonicalTrack.getResolvedTextPath(
        project!.directoryPath,
        collection.folderName,
      );

      if (resolvedAudio == null || resolvedText == null) {
        track.status = AlignmentStatus.error;
        canonicalTrack.status = AlignmentStatus.error;
        notifyListeners();
        continue;
      }

      track.status = AlignmentStatus.processing;
      canonicalTrack.status = AlignmentStatus.processing;
      batchStatus = "Processing ${canonicalTrack.name}...";
      batchProgress = 0.0;
      notifyListeners();

      File? tempCleanTextFile;
      List<String> extractedIds = [];
      String actualTextPath = resolvedText;

      try {
        bool shouldExtractIds = false;
        try {
          final sample = await File(resolvedText).readAsString();
          if (detectTabDelimitedIds(sample)) {
            shouldExtractIds = true;
          } else {
            final lines = await File(resolvedText).readAsLines();
            for (final line in lines) {
              if (line.trim().isEmpty) continue;
              final parsed = extractIdFromLine(line);
              if (parsed.hasId) {
                shouldExtractIds = true;
                break;
              }
            }
          }
        } catch (_) {}

        if (shouldExtractIds) {
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
          final tempDir = Directory.systemTemp;
          tempCleanTextFile = File(
            p.join(tempDir.path, 'clean_${uuid.v4()}.txt'),
          );
          await tempCleanTextFile.writeAsString(cleanLines.join('\n'));
          actualTextPath = tempCleanTextFile.path;
        }

        List<Fragment> fragments = await alignmentService.align(
          textPath: actualTextPath,
          audioPath: resolvedAudio,
          languageCode: project!.languageCode,
          leadInSeconds: project!.boundaryLeadInMs / 1000.0,
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
          canonicalTrack.status = AlignmentStatus.pending;
          notifyListeners();
          break;
        }

        if (shouldExtractIds && extractedIds.isNotEmpty) {
          for (int i = 0; i < fragments.length; i++) {
            if (i < extractedIds.length && extractedIds[i].isNotEmpty) {
              fragments[i] = fragments[i].copyWith(id: extractedIds[i]);
            }
          }
        } else if (project!.defaultIdPrefix != null &&
            project!.defaultIdPrefix!.isNotEmpty) {
          final prefix = project!.defaultIdPrefix!;
          int trackIdx = collection.tracks.indexOf(canonicalTrack) + 1;
          if (trackIdx <= 0) trackIdx = collection.tracks.indexOf(track) + 1;
          final recStr = trackIdx.toString().padLeft(3, '0');
          for (int j = 0; j < fragments.length; j++) {
            final verseStr = (j + 1).toString().padLeft(3, '0');
            fragments[j] = fragments[j].copyWith(id: '$prefix$recStr$verseStr');
          }
        }

        final absPath = canonicalTrack.getAbsoluteOutputPath(
          project!.directoryPath,
          collection.folderName,
        );
        final alignDir = Directory(p.dirname(absPath));
        if (!await alignDir.exists()) await alignDir.create(recursive: true);

        final List<Map<String, dynamic>> jsonList =
            fragments.map((f) => f.toJson()).toList();

        FileSyncTracker.markLocallyWritten(absPath);
        await File(
          absPath,
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(jsonList));
        track.status = AlignmentStatus.done;
        canonicalTrack.status = AlignmentStatus.done;
      } catch (e) {
        if (!isBatchRunning) {
          track.status = AlignmentStatus.pending;
          canonicalTrack.status = AlignmentStatus.pending;
          break;
        } else {
          track.status = AlignmentStatus.error;
          canonicalTrack.status = AlignmentStatus.error;
        }
      } finally {
        if (tempCleanTextFile != null && await tempCleanTextFile.exists()) {
          await tempCleanTextFile.delete();
        }
      }

      final colFile = p.join(
        project!.directoryPath,
        'collections',
        collection.folderName,
        'collection.json',
      );
      FileSyncTracker.markLocallyWritten(colFile);
      await collection.saveTracks(project!.directoryPath);
      notifyListeners();
    }

    isBatchRunning = false;
    batchStatus = "Batch Complete";
    batchProgress = 1.0;
    notifyListeners();

    if (_pendingChangedPaths.isNotEmpty) {
      _watcherDebounceTimer = Timer(watcherDebounceDuration, () {
        _handleRemoteSyncBatch();
      });
    }
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
      await collection.saveTracks(project!.directoryPath);
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
    if (selection.type == NodeType.collection && selection.collection != null) {
      expandedNodes.add(selection.collection!.id);
    }
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

  // ---------------------------------------------------------------------------
  // DIRECTORY WATCHER & LIVE SYNC
  // ---------------------------------------------------------------------------

  void _startDirectoryWatcher() {
    _stopDirectoryWatcher();
    if (project == null || project!.directoryPath.isEmpty) return;

    final projectDir = Directory(project!.directoryPath);
    if (!projectDir.existsSync()) return;

    try {
      _watcherSubscription = projectDir.watch(recursive: true).listen(
        _onFileSystemEvent,
        onError: (e) {
          debugPrint('[SYNC] Directory watcher error: $e');
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('[SYNC] Failed to start directory watcher: $e');
    }
  }

  void _stopDirectoryWatcher() {
    _watcherDebounceTimer?.cancel();
    _watcherDebounceTimer = null;
    _watcherSubscription?.cancel();
    _watcherSubscription = null;
    _pendingChangedPaths.clear();
  }

  void _onFileSystemEvent(FileSystemEvent event) {
    if (!event.path.endsWith('.json')) return;
    if (FileSyncTracker.isLocallyWritten(event.path)) return;
    _pendingChangedPaths.add(event.path);
    _watcherDebounceTimer?.cancel();
    _watcherDebounceTimer = Timer(watcherDebounceDuration, () {
      _handleRemoteSyncBatch();
    });
  }

  Future<void> _handleRemoteSyncBatch([Set<String>? testPaths]) async {
    if (project == null || (isBatchRunning && testPaths == null)) return;
    final pathsToProcess = testPaths ?? Set<String>.from(_pendingChangedPaths);
    _pendingChangedPaths.clear();

    if (pathsToProcess.isEmpty) return;

    bool needsNotify = false;

    for (final path in pathsToProcess) {
      final normalizedPath = p.canonicalize(path);

      // 1. Collection metadata updated remotely
      if (normalizedPath.endsWith('collection.json')) {
        for (final col in project!.collections) {
          final expectedColPath = p.canonicalize(
            p.join(
              project!.directoryPath,
              'collections',
              col.folderName,
              'collection.json',
            ),
          );
          if (normalizedPath == expectedColPath) {
            await project!.reloadCollection(col);
            needsNotify = true;
            break;
          }
        }
      }
      // 2. Project settings / collections updated remotely
      else if (normalizedPath ==
          p.canonicalize(p.join(project!.directoryPath, 'project.json'))) {
        try {
          final file = File(normalizedPath);
          if (file.existsSync()) {
            final content = await file.readAsString();
            final json = jsonDecode(content) as Map<String, dynamic>;
            final remoteProject = Project.fromJson(json);
            final existingColIds =
                project!.collections.map((c) => c.id).toSet();
            for (final remoteCol in remoteProject.collections) {
              if (!existingColIds.contains(remoteCol.id)) {
                project!.collections.add(remoteCol);
                needsNotify = true;
              }
            }
          }
        } catch (e) {
          debugPrint('[SYNC] Failed to sync remote project.json: $e');
        }
      }
      // 4. Track alignment output updated remotely
      else if (normalizedPath.endsWith('.json')) {
        final parentDir = p.basename(p.dirname(normalizedPath));
        if (parentDir == 'alignments') {
          final filename = p.basename(normalizedPath);
          for (final col in project!.collections) {
            for (final track in col.tracks) {
              if (track.outputFilename == filename) {
                if (File(normalizedPath).existsSync() &&
                    track.status == AlignmentStatus.pending) {
                  track.status = AlignmentStatus.done;
                  needsNotify = true;
                }
              }
            }
          }
        }
      }
    }

    if (needsNotify || pathsToProcess.isNotEmpty) {
      notifyListeners();
    }
  }

  @visibleForTesting
  Future<void> handleRemoteSyncForTest(String path) async {
    await _handleRemoteSyncBatch({path});
  }
}
