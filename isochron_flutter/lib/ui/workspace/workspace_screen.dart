import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:isochron_flutter/services/alignment_service.dart';
import 'package:isochron_flutter/services/export_service.dart';
import 'package:isochron_flutter/services/pins_service.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'package:isochron_flutter/utils/id_extraction.dart';
import 'package:isochron_flutter/ui/app_manager.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:isochron_cli/isochron_cli.dart';

// --- Extracted Feature Views ---
import 'models/workspace_models.dart';
import 'components/inline_text_editor.dart';
import '../editor/studio_editor.dart';
import 'views/welcome_view.dart';
import 'views/project_settings_view.dart';
import 'views/audio_inspector_view.dart';
import 'views/text_editor_view.dart';
import 'views/collection_batch_view.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  Project? _project;
  late final AppManager _homeManager;
  final Uuid _uuid = const Uuid();
  bool _hasUnsavedChanges = false;
  final _alignmentService = AlignmentService();

  // Tree State
  TreeSelection? _selectedNode;
  final Set<String> _expandedNodes = {};
  String? _expandedTrackId;
  String? _editingNodeId;

  // Batch State
  bool _isBatchRunning = false;
  String _batchStatus = "";
  double _batchProgress = 0.0;

  // Menu Cache
  List<PlatformMenuItem>? _cachedMenus;
  Project? _lastMenuProject;
  bool? _lastMenuHasUnsaved;
  NodeType? _lastMenuNodeType;

  @override
  void initState() {
    super.initState();
    _homeManager = AppManager();
    _homeManager.onSaveCallback = () {
      if (_selectedNode?.track != null) {
        setState(() => _selectedNode!.track!.status = AlignmentStatus.reviewed);
        _project?.save();
      }
    };
    _homeManager.addListener(() {
      if (_homeManager.value.hasUnsavedChanges != _hasUnsavedChanges) {
        setState(
          () => _hasUnsavedChanges = _homeManager.value.hasUnsavedChanges,
        );
      }
    });
  }

  @override
  void dispose() {
    _homeManager.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // PROJECT LIFECYCLE
  // ---------------------------------------------------------------------------

  Future<void> _createNewProject() async {
    final settings = UserSettingsService();

    final String? projectPath = await FilePicker.saveFile(
      dialogTitle: 'Create New Project',
      fileName: 'Untitled Project',
      initialDirectory: settings.lastProjectDir,
      lockParentWindow: true,
    );

    if (projectPath == null) return;

    final projectDir = Directory(projectPath);
    final projectName = p.basename(projectPath);

    if (await projectDir.exists()) {
      if (mounted) {
        showMacosAlertDialog(
          context: context,
          builder: (context) => MacosAlertDialog(
            appIcon: const MacosIcon(CupertinoIcons.folder_badge_minus),
            title: const Text('Folder Already Exists'),
            message: Text(
              'A project or folder named "$projectName" already exists in this location.\n\nPlease choose a different name or location.',
              textAlign: TextAlign.center,
            ),
            primaryButton: PushButton(
              controlSize: ControlSize.large,
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ),
        );
      }
      return;
    }

    settings.setLastProjectDir(p.dirname(projectPath));

    await projectDir.create(recursive: true);
    await Directory(p.join(projectDir.path, 'collections')).create();

    final newProject = Project(
      id: _uuid.v4(),
      name: projectName,
      directoryPath: projectDir.path,
    );

    final defaultCollection = Collection(
      id: _uuid.v4(),
      name: "First Collection",
    );
    newProject.collections.add(defaultCollection);

    await newProject.save();

    setState(() {
      _project = newProject;
      _expandedNodes.add(defaultCollection.id);
      _selectedNode = TreeSelection(
        type: NodeType.collection,
        collection: defaultCollection,
      );
    });
  }

  Future<void> _openProject() async {
    try {
      final settings = UserSettingsService();
      final result = await FilePicker.pickFiles(
        dialogTitle: 'Open Project',
        type: FileType.custom,
        allowedExtensions: ['json'],
        initialDirectory: settings.lastProjectDir,
      );

      if (result != null && result.files.single.path != null) {
        settings.setLastProjectDir(p.dirname(result.files.single.path!));
        final content = await File(result.files.single.path!).readAsString();
        final parsed = jsonDecode(content);

        setState(() {
          _project = Project.fromJson(parsed);
          if (_project!.collections.isNotEmpty) {
            _expandedNodes.add(_project!.collections.first.id);
            _selectedNode = TreeSelection(
              type: NodeType.collection,
              collection: _project!.collections.first,
            );
          }
        });
      }
    } catch (e) {
      debugPrint("Error: $e");
    }
  }

  Future<void> _importCollectionsFromProject() async {
    if (_project == null) return;

    final settings = UserSettingsService();
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Import Collections from Project',
      type: FileType.custom,
      allowedExtensions: ['json'],
      initialDirectory: settings.lastProjectDir,
    );

    if (result != null && result.files.single.path != null) {
      try {
        final importedFilePath = result.files.single.path!;
        final importedProjectDir = p.dirname(importedFilePath);
        final content = await File(importedFilePath).readAsString();
        final parsed = jsonDecode(content);

        final importedProject = Project.fromJson(parsed);

        List<Collection> newCollections = [];
        int importedTrackCount = 0;

        for (var col in importedProject.collections) {
          final newCol = Collection(id: _uuid.v4(), name: col.name);
          final newColDir = Directory(
            p.join(_project!.directoryPath, 'collections', newCol.id),
          );

          final alignmentsDir = Directory(p.join(newColDir.path, 'alignments'));
          if (!await alignmentsDir.exists())
            await alignmentsDir.create(recursive: true);

          for (var track in col.tracks) {
            // 1. COPY ALIGNMENT JSONS
            File oldJsonFile = File(
              p.join(importedProjectDir, 'alignments', track.outputFilename),
            );
            if (!await oldJsonFile.exists()) {
              oldJsonFile = File(
                p.join(importedProjectDir, track.outputFilename),
              );
            }

            final safeFilename =
                '${_uuid.v4().substring(0, 8)}_${track.outputFilename}';
            final newJsonPath = p.join(alignmentsDir.path, safeFilename);

            if (await oldJsonFile.exists()) {
              await oldJsonFile.copy(newJsonPath);
              final oldPinsFile = File(PinsService.pinsPath(oldJsonFile.path));
              if (await oldPinsFile.exists()) {
                await oldPinsFile.copy(PinsService.pinsPath(newJsonPath));
              }
            }

            // 2. COPY MEDIA (If setting is enabled)
            String? finalAudio = track.audioPath;
            String? finalText = track.textPath;

            if (_project!.copyMediaIntoProject) {
              if (finalAudio != null) {
                // Resolve the old absolute path (handling edge cases where the old project used relative paths)
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
                  if (!await audioDir.exists())
                    await audioDir.create(recursive: true);

                  finalAudio = p.basename(oldAudioFile.path); // Set to relative
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
                  if (!await textDir.exists())
                    await textDir.create(recursive: true);

                  finalText = p.basename(oldTextFile.path); // Set to relative
                  await oldTextFile.copy(p.join(textDir.path, finalText));
                }
              }
            }

            newCol.tracks.add(
              Track(
                id: _uuid.v4(),
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

        setState(() {
          _project!.collections.addAll(newCollections);
          for (var c in newCollections) _expandedNodes.add(c.id);
        });

        await _project!.save();

        if (mounted) {
          showMacosAlertDialog(
            context: context,
            builder: (context) => MacosAlertDialog(
              appIcon: const MacosIcon(CupertinoIcons.check_mark_circled),
              title: const Text('Import Complete'),
              message: Text(
                'Successfully imported ${newCollections.length} collection(s) containing $importedTrackCount tracks.',
                textAlign: TextAlign.center,
              ),
              primaryButton: PushButton(
                controlSize: ControlSize.large,
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ),
          );
        }
      } catch (e) {
        debugPrint("Error importing collections: $e");
        if (mounted) {
          showMacosAlertDialog(
            context: context,
            builder: (context) => MacosAlertDialog(
              appIcon: const MacosIcon(CupertinoIcons.exclamationmark_triangle),
              title: const Text('Import Failed'),
              message: Text(
                'Could not parse the selected project file.\n\nError: $e',
                textAlign: TextAlign.center,
              ),
              primaryButton: PushButton(
                controlSize: ControlSize.large,
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ),
          );
        }
      }
    }
  }

  Future<bool> _requestCloseEditor() async {
    if (_selectedNode?.type == NodeType.track && _hasUnsavedChanges) {
      final result = await showCupertinoDialog<String>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Unsaved Changes'),
          content: const Text(
            'You have unsaved changes in your alignment. Save before leaving?',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(context, 'discard'),
              child: const Text('Discard'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(context, 'save'),
              child: const Text('Save'),
            ),
          ],
        ),
      );

      if (result == 'save') {
        await _homeManager.saveProject();
        return true;
      } else if (result == 'discard') {
        await _homeManager.discardChanges();
        return true;
      } else {
        return false;
      }
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // INVALIDATION LOGIC
  // ---------------------------------------------------------------------------

  Future<void> _invalidateAndReplace(
    Track track,
    Future<void> Function() action,
  ) async {
    if (track.status != AlignmentStatus.pending) {
      final bool? confirm = await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Invalidate Alignment?'),
          content: const Text(
            'Modifying this file will invalidate your existing alignment data. Are you sure?',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Modify'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    await action();

    final jsonPath = track.getAbsoluteOutputPath(_project!.directoryPath);
    final pinsPath = PinsService.pinsPath(jsonPath);
    if (await File(jsonPath).exists()) await File(jsonPath).delete();
    if (await File(pinsPath).exists()) await File(pinsPath).delete();

    setState(() => track.status = AlignmentStatus.pending);
    await _project!.save();
  }

  // ---------------------------------------------------------------------------
  // BATCH & EXPORT LOGIC
  // ---------------------------------------------------------------------------

  Future<void> _runBatch(Collection collection) async {
    setState(() {
      _isBatchRunning = true;
      _batchStatus = "Starting Batch...";
      _batchProgress = 0.0;
    });

    final pendingTracks = collection.tracks
        .where(
          (t) =>
              t.status == AlignmentStatus.pending ||
              t.status == AlignmentStatus.error,
        )
        .toList();

    for (var track in pendingTracks) {
      if (!_isBatchRunning) break;

      // --- Resolve paths for the batch! ---
      final resolvedAudio = track.getResolvedAudioPath(_project!.directoryPath);
      final resolvedText = track.getResolvedTextPath(_project!.directoryPath);

      if (resolvedAudio == null || resolvedText == null) {
        setState(() => track.status = AlignmentStatus.error);
        continue;
      }

      setState(() {
        track.status = AlignmentStatus.processing;
        _batchStatus = "Processing ${track.name}...";
      });

      File? tempCleanTextFile;
      List<String> extractedIds = [];
      String actualTextPath = resolvedText;

      try {
        if (_project!.defaultHasIds) {
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
            p.join(tempDir.path, 'clean_${_uuid.v4()}.txt'),
          );
          await tempCleanTextFile.writeAsString(cleanLines.join('\n'));
          actualTextPath = tempCleanTextFile.path;
        }

        List<Fragment> fragments = await _alignmentService.runIsochron(
          textPath: actualTextPath,
          audioPath: resolvedAudio, // Use the resolved audio path
          dictPath: _project!.dictPath,
          snapMode: _project!.snapMode,
          snapOffsetMs: _project!.snapOffset ?? 0,
          onProgress: (status, prog) {
            if (_isBatchRunning && mounted) {
              setState(() {
                _batchStatus = status;
                _batchProgress = prog;
              });
            }
          },
        );

        if (!_isBatchRunning) {
          setState(() => track.status = AlignmentStatus.pending);
          break;
        }

        if (_project!.defaultHasIds && extractedIds.isNotEmpty) {
          for (int i = 0; i < fragments.length; i++) {
            if (i < extractedIds.length) {
              fragments[i] = fragments[i].copyWith(id: extractedIds[i]);
            }
          }
        }

        if (!_project!.defaultHasIds && _project!.defaultGenerateIds) {
          final prefix = _project!.defaultIdPrefix ?? "";
          int trackIdx = collection.tracks.indexOf(track) + 1;
          final recStr = trackIdx.toString().padLeft(3, '0');
          for (int j = 0; j < fragments.length; j++) {
            final verseStr = (j + 1).toString().padLeft(3, '0');
            fragments[j] = fragments[j].copyWith(id: '$prefix$recStr$verseStr');
          }
        }

        // Figure out where to save the alignment JSON
        final absPath = track.getAbsoluteOutputPath(_project!.directoryPath);

        // --- Ensure the nested alignments directory exists! ---
        final alignDir = Directory(p.dirname(absPath));
        if (!await alignDir.exists()) {
          await alignDir.create(recursive: true);
        }

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

        setState(() => track.status = AlignmentStatus.done);
      } catch (e) {
        if (!_isBatchRunning) {
          setState(() => track.status = AlignmentStatus.pending);
          break;
        } else {
          setState(() => track.status = AlignmentStatus.error);
        }
      } finally {
        if (tempCleanTextFile != null && await tempCleanTextFile.exists()) {
          await tempCleanTextFile.delete();
        }
      }

      await _project!.save();
    }

    setState(() {
      _isBatchRunning = false;
      _batchStatus = "Batch Complete";
      _batchProgress = 1.0;
    });
  }

  Future<void> _exportPhraseTimingForTrack(Track track) async {
    if (_project == null) return;
    if (!ExportService.canExportPhraseTiming(track)) return;

    final defaultName = ExportService.defaultPhraseTimingFilenameForTrack(
      track,
    );

    final outputFile = await FilePicker.saveFile(
      dialogTitle: 'Export Phrase Timing',
      fileName: defaultName,
      type: FileType.custom,
      allowedExtensions: ['txt'],
      initialDirectory: _project!.directoryPath,
    );
    if (outputFile == null) return;

    final payload = await ExportService.buildPhraseTiming(_project!, track);
    if (payload == null || payload.isEmpty) return;
    await File(outputFile).writeAsString(payload);
  }

  // ---------------------------------------------------------------------------
  // SIDEBAR & TREE VIEWS
  // ---------------------------------------------------------------------------

  void _addCollection() {
    setState(() {
      final newCol = Collection(id: _uuid.v4(), name: "New Collection");
      _project!.collections.add(newCol);
      _expandedNodes.add(newCol.id);
      _project!.save();
    });
  }

  Future<void> _deleteCollection(Collection collection) async {
    final bool? confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Delete Collection?'),
        content: Text(
          'Are you sure you want to delete "${collection.name}" and all of its tracks?\n\nThis will remove them from the project, but your raw audio and text files will remain safe on your hard drive.',
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _project!.collections.remove(collection);
      if (_selectedNode?.collection == collection) {
        _selectedNode = null;
      }
      _expandedNodes.remove(collection.id);
    });

    _project!.save();
  }

  Future<void> _deleteTrack(Track track, Collection collection) async {
    final bool? confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Delete Track?'),
        content: Text(
          'Are you sure you want to remove "${track.name}" from this collection?',
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final jsonPath = track.getAbsoluteOutputPath(_project!.directoryPath);
    final pinsPath = PinsService.pinsPath(jsonPath);
    if (await File(jsonPath).exists()) await File(jsonPath).delete();
    if (await File(pinsPath).exists()) await File(pinsPath).delete();

    setState(() {
      collection.tracks.remove(track);
      if (_selectedNode?.track == track) {
        _expandedTrackId = null;
        _selectedNode = TreeSelection(
          type: NodeType.collection,
          collection: collection,
        );
      }
    });

    _project!.save();
  }

  Sidebar _buildTreeSidebar(BuildContext context) {
    List<Widget> rows = [];
    final theme = MacosTheme.of(context);

    for (var col in _project!.collections) {
      final isColSelected =
          _selectedNode?.collection == col &&
          _selectedNode?.type == NodeType.collection;

      rows.add(
        _buildTreeRow(
          label: col.name,
          icon: isColSelected
              ? CupertinoIcons.folder_solid
              : CupertinoIcons.folder,
          iconColor: theme.typography.body.color ?? CupertinoColors.black,
          isSelected: isColSelected,
          isExpanded: _expandedNodes.contains(col.id),
          depth: 0,
          hasChildren: true,
          isEditing: _editingNodeId == col.id,
          onDoubleTap: () => setState(() => _editingNodeId = col.id),
          onEditComplete: (newName) {
            setState(() {
              if (newName.trim().isNotEmpty) col.name = newName.trim();
              _editingNodeId = null;
            });
            _project!.save();
          },
          onTap: () async {
            if (_editingNodeId != null) {
              setState(() => _editingNodeId = null);
              return;
            }

            if (isColSelected) {
              setState(() {
                if (_expandedNodes.contains(col.id)) {
                  _expandedNodes.remove(col.id);
                } else {
                  _expandedNodes.add(col.id);
                }
              });
              return;
            }

            if (_hasUnsavedChanges && _selectedNode?.type == NodeType.track) {
              final proceed = await _requestCloseEditor();
              if (!proceed) return;
            }

            setState(() {
              if (!_expandedNodes.contains(col.id)) _expandedNodes.add(col.id);
              _selectedNode = TreeSelection(
                type: NodeType.collection,
                collection: col,
              );
            });
          },
        ),
      );

      if (_expandedNodes.contains(col.id)) {
        for (var track in col.tracks) {
          final isTrackSelected =
              _selectedNode?.track == track &&
              _selectedNode?.type == NodeType.track;

          rows.add(
            _buildTreeRow(
              label: track.name,
              icon: CupertinoIcons.waveform_path,
              iconColor: _getTrackColor(context, track.status),
              isSelected: isTrackSelected,
              isExpanded: _expandedTrackId == track.id,
              depth: 1,
              hasChildren: true,
              isEditing: _editingNodeId == track.id,
              onDoubleTap: () => setState(() => _editingNodeId = track.id),
              onEditComplete: (newName) {
                setState(() {
                  if (newName.trim().isNotEmpty) track.name = newName.trim();
                  _editingNodeId = null;
                });
                _project!.save();
              },
              onTap: () async {
                if (_editingNodeId != null) {
                  setState(() => _editingNodeId = null);
                  return;
                }

                final bool isAlreadyExpanded = _expandedTrackId == track.id;

                if (isTrackSelected) {
                  setState(() {
                    _expandedTrackId = isAlreadyExpanded ? null : track.id;
                  });
                  return;
                }

                if (_hasUnsavedChanges &&
                    _selectedNode?.type == NodeType.track) {
                  final proceed = await _requestCloseEditor();
                  if (!proceed) return;
                }

                _homeManager.value = _homeManager.value.copyWith(
                  clearWaveform: true,
                  clearFocus: true,
                  fragments: [],
                  statusMessage: "Loading...",
                );

                setState(() {
                  _expandedTrackId = track.id;
                  _selectedNode = TreeSelection(
                    type: NodeType.track,
                    collection: col,
                    track: track,
                  );
                });

                Future.delayed(const Duration(milliseconds: 50), () {
                  if (mounted) _homeManager.loadTrack(track, _project!);
                });
              },
            ),
          );

          if (_expandedTrackId == track.id) {
            // Audio Node
            final isAudioSelected =
                _selectedNode?.track == track &&
                _selectedNode?.type == NodeType.audio;
            rows.add(
              _buildTreeRow(
                label: track.audioPath != null
                    ? p.basename(
                        track.getResolvedAudioPath(_project!.directoryPath)!,
                      )
                    : '[⚠️ Missing Audio]',
                icon: CupertinoIcons.speaker_2_fill,
                iconColor: track.audioPath != null
                    ? CupertinoColors.systemGrey
                    : CupertinoColors.destructiveRed,
                isSelected: isAudioSelected,
                isExpanded: false,
                depth: 2,
                hasChildren: false,
                onTap: () async {
                  if (_hasUnsavedChanges &&
                      _selectedNode?.type == NodeType.track) {
                    final proceed = await _requestCloseEditor();
                    if (!proceed) return;
                  }
                  setState(
                    () => _selectedNode = TreeSelection(
                      type: NodeType.audio,
                      collection: col,
                      track: track,
                    ),
                  );
                },
              ),
            );

            // Text Node
            final isTextSelected =
                _selectedNode?.track == track &&
                _selectedNode?.type == NodeType.text;
            rows.add(
              _buildTreeRow(
                label: track.textPath != null
                    ? p.basename(
                        track.getResolvedTextPath(_project!.directoryPath)!,
                      )
                    : '[⚠️ Missing Text]',
                icon: CupertinoIcons.doc_text_fill,
                iconColor: track.textPath != null
                    ? CupertinoColors.systemGrey
                    : CupertinoColors.destructiveRed,
                isSelected: isTextSelected,
                isExpanded: false,
                depth: 2,
                hasChildren: false,
                onTap: () async {
                  if (_hasUnsavedChanges &&
                      _selectedNode?.type == NodeType.track) {
                    final proceed = await _requestCloseEditor();
                    if (!proceed) return;
                  }
                  setState(
                    () => _selectedNode = TreeSelection(
                      type: NodeType.text,
                      collection: col,
                      track: track,
                    ),
                  );
                },
              ),
            );
          }
        }
      }
    }

    return Sidebar(
      minWidth: 220,
      startWidth: 260,
      maxWidth: 350,
      top: Padding(
        padding: const EdgeInsets.only(
          left: 16.0,
          right: 8.0,
          top: 12.0,
          bottom: 8.0,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _project!.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            MacosTooltip(
              message: "New Collection",
              child: MacosIconButton(
                icon: MacosIcon(
                  CupertinoIcons.folder_badge_plus,
                  size: 18,
                  color: theme.typography.body.color,
                ),
                onPressed: _addCollection,
                boxConstraints: const BoxConstraints(
                  minHeight: 28,
                  minWidth: 28,
                ),
              ),
            ),
          ],
        ),
      ),
      builder: (context, scrollController) => ListView.builder(
        controller: scrollController,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: rows.length,
        itemBuilder: (context, index) => rows[index],
      ),
    );
  }

  Widget _buildTreeRow({
    required String label,
    required IconData icon,
    required Color iconColor,
    required bool isSelected,
    required bool isExpanded,
    required int depth,
    required bool hasChildren,
    required VoidCallback onTap,
    VoidCallback? onDoubleTap,
    bool isEditing = false,
    ValueChanged<String>? onEditComplete,
  }) {
    final theme = MacosTheme.of(context);
    final blue = CupertinoColors.systemBlue.resolveFrom(context);
    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 28,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        padding: EdgeInsets.only(left: depth * 16.0 + 8.0, right: 8.0),
        decoration: BoxDecoration(
          color: isSelected ? blue : CupertinoColors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            if (hasChildren)
              Icon(
                isExpanded
                    ? CupertinoIcons.chevron_down
                    : CupertinoIcons.chevron_right,
                size: 12,
                color: isSelected
                    ? CupertinoColors.white
                    : CupertinoColors.systemGrey,
              )
            else
              const SizedBox(width: 12),
            const SizedBox(width: 4),
            Icon(
              icon,
              size: 14,
              color: isSelected ? CupertinoColors.white : iconColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: isEditing
                  ? InlineTextEditor(
                      initialText: label,
                      onComplete: onEditComplete!,
                    )
                  : Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: isSelected
                            ? CupertinoColors.white
                            : theme.typography.body.color,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getTrackColor(BuildContext context, AlignmentStatus status) {
    final isDark = MacosTheme.of(context).brightness == Brightness.dark;
    switch (status) {
      case AlignmentStatus.done:
      case AlignmentStatus.reviewed:
        return isDark
            ? CupertinoColors.activeGreen
            : const Color(0xFF198754); // Deeper Green
      case AlignmentStatus.processing:
        return isDark
            ? CupertinoColors.activeBlue
            : const Color(0xFF0056B3); // Deeper Blue
      case AlignmentStatus.error:
        return isDark
            ? CupertinoColors.destructiveRed
            : const Color(0xFFDC3545); // Deeper Red
      case AlignmentStatus.pending:
        return isDark
            ? CupertinoColors.systemYellow
            : const Color(0xFFD97706); // Dark Amber instead of pale yellow
    }
  }

  // ---------------------------------------------------------------------------
  // CENTER ROUTER
  // ---------------------------------------------------------------------------

  Widget _buildCenterPane() {
    if (_selectedNode == null) {
      return const Center(child: Text("Select a collection or track."));
    }

    switch (_selectedNode!.type) {
      case NodeType.collection:
        return CollectionBatchView(
          collection: _selectedNode!.collection!,
          project: _project!,
          isRunning: _isBatchRunning,
          status: _batchStatus,
          progress: _batchProgress,
          onRunBatch: () => _runBatch(_selectedNode!.collection!),
          onStopBatch: () {
            setState(() => _isBatchRunning = false);
            _alignmentService.cancelCurrentRun();
          },
          onChanged: () {
            setState(() {});
            _project!.save();
          },
          onOpenTrack: (track) {
            _homeManager.value = _homeManager.value.copyWith(
              clearWaveform: true,
              clearFocus: true,
              fragments: [],
              statusMessage: "Loading...",
            );

            setState(() {
              _expandedTrackId = track.id;
              _selectedNode = TreeSelection(
                type: NodeType.track,
                collection: _selectedNode!.collection,
                track: track,
              );
            });

            Future.delayed(const Duration(milliseconds: 50), () {
              if (mounted) _homeManager.loadTrack(track, _project!);
            });
          },
        );
      case NodeType.track:
        return StudioEditor(homeManager: _homeManager);
      case NodeType.text:
        return TextEditorView(
          track: _selectedNode!.track!,
          project: _project!,
          collection: _selectedNode!.collection!,
          onReplaceOrEdit: (action) =>
              _invalidateAndReplace(_selectedNode!.track!, action),
        );
      case NodeType.audio:
        return AudioInspectorView(
          track: _selectedNode!.track!,
          project: _project!,
          collection: _selectedNode!.collection!,
          onReplace: (action) =>
              _invalidateAndReplace(_selectedNode!.track!, action),
        );
      case NodeType.settings:
        return ProjectSettingsView(
          project: _project!,
          onSaved: () {
            setState(() {});
            _project!.save();
          },
        );
    }
  }

  // ---------------------------------------------------------------------------
  // NATIVE MENU BAR & ROOT BUILD
  // ---------------------------------------------------------------------------

  List<PlatformMenuItem> _buildMenus() {
    if (_cachedMenus != null &&
        _lastMenuProject == _project &&
        _lastMenuHasUnsaved == _hasUnsavedChanges &&
        _lastMenuNodeType == _selectedNode?.type) {
      return _cachedMenus!;
    }

    _lastMenuProject = _project;
    _lastMenuHasUnsaved = _hasUnsavedChanges;
    _lastMenuNodeType = _selectedNode?.type;

    _cachedMenus = [
      PlatformMenu(
        label: 'Isochron Studio',
        menus: [
          const PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.about,
          ),
          if (_project != null)
            PlatformMenuItem(
              label: 'Settings...',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.comma,
                meta: true,
              ),
              onSelected: () async {
                if (await _requestCloseEditor()) {
                  setState(
                    () =>
                        _selectedNode = TreeSelection(type: NodeType.settings),
                  );
                }
              },
            ),
          const PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.quit,
          ),
        ],
      ),
      PlatformMenu(
        label: 'File',
        menus: [
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'New Project...',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyN,
                  meta: true,
                ),
                onSelected: _createNewProject,
              ),
              PlatformMenuItem(
                label: 'Open Project...',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyO,
                  meta: true,
                ),
                onSelected: _openProject,
              ),
            ],
          ),
          if (_project != null)
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: 'Import Collections from Project...',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyI,
                    meta: true,
                    shift: true,
                  ),
                  onSelected: _importCollectionsFromProject,
                ),
                PlatformMenuItem(
                  label: 'Save',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyS,
                    meta: true,
                  ),
                  onSelected:
                      (_selectedNode?.type == NodeType.track &&
                          !_hasUnsavedChanges)
                      ? null
                      : () {
                          if (_selectedNode?.type == NodeType.track) {
                            _homeManager.saveProject();
                          } else {
                            _project!.save();
                          }
                        },
                ),
              ],
            ),
          if (_project != null)
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: 'Export CSV...',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyE,
                    meta: true,
                    shift: true,
                  ),
                  onSelected: () async {
                    final out = await FilePicker.saveFile(
                      dialogTitle: 'Export CSV',
                      fileName: ExportService.defaultCsvFilename(
                        _project!.name,
                      ),
                      type: FileType.custom,
                      allowedExtensions: ['csv'],
                      initialDirectory: _project!.directoryPath,
                    );
                    if (out != null) {
                      final payload = await ExportService.buildCombinedCsv(
                        _project!,
                      );
                      await File(out).writeAsString(payload);
                    }
                  },
                ),
              ],
            ),
          if (_project != null)
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: 'Close Project',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyW,
                    meta: true,
                  ),
                  onSelected: () async {
                    if (await _requestCloseEditor()) {
                      setState(() {
                        _project = null;
                        _selectedNode = null;
                        _expandedNodes.clear();
                      });
                    }
                  },
                ),
              ],
            ),
        ],
      ),
    ];

    return _cachedMenus!;
  }

  @override
  Widget build(BuildContext context) {
    final Widget activeScreen = _project == null
        ? WelcomeView(
            onCreateNewProject: _createNewProject,
            onOpenProject: _openProject,
          )
        : MacosWindow(
            key: const ValueKey('main_workspace_window'),
            sidebar: _buildTreeSidebar(context),
            child: MacosScaffold(
              toolBar: ToolBar(
                title: Text(
                  _selectedNode?.type == NodeType.track
                      ? _selectedNode!.track!.name
                      : (_selectedNode?.type == NodeType.settings
                            ? "Settings"
                            : "Isochron Studio"),
                ),
                actions: [
                  // --- TRACK ACTIONS ---
                  if (_selectedNode?.type == NodeType.track) ...[
                    ToolBarIconButton(
                      label: 'Save',
                      icon: MacosIcon(
                        CupertinoIcons.floppy_disk,
                        color: _hasUnsavedChanges
                            ? MacosTheme.of(context).typography.body.color
                            : CupertinoColors.systemGrey.withValues(alpha: 0.5),
                      ),
                      showLabel: true,
                      onPressed: _hasUnsavedChanges
                          ? () => _homeManager.saveProject()
                          : null,
                    ),
                    ToolBarIconButton(
                      label: 'Auto-Align',
                      icon: MacosIcon(
                        CupertinoIcons.wand_rays,
                        color: MacosTheme.of(context).typography.body.color,
                      ),
                      showLabel: true,
                      onPressed: () async {
                        try {
                          await _homeManager.runAlignment(
                            snapMode: _project!.snapMode,
                            snapOffsetMs: _project!.snapOffset ?? 0,
                          );
                        } catch (e) {
                          if (context.mounted) {
                            showCupertinoDialog(
                              context: context,
                              builder: (_) => CupertinoAlertDialog(
                                title: const Text("Alignment Error"),
                                content: Text(e.toString()),
                                actions: [
                                  CupertinoDialogAction(
                                    isDefaultAction: true,
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text("OK"),
                                  ),
                                ],
                              ),
                            );
                          }
                        }
                      },
                    ),
                    ToolBarIconButton(
                      label: 'Export Timing',
                      icon: MacosIcon(
                        CupertinoIcons.square_arrow_down,
                        color:
                            ExportService.canExportPhraseTiming(
                              _selectedNode!.track!,
                            )
                            ? MacosTheme.of(context).typography.body.color
                            : CupertinoColors.systemGrey.withValues(alpha: 0.5),
                      ),
                      showLabel: true,
                      tooltipMessage: ExportService.phraseExportTooltip(
                        _selectedNode!.track!,
                      ),
                      onPressed:
                          ExportService.canExportPhraseTiming(
                            _selectedNode!.track!,
                          )
                          ? () => _exportPhraseTimingForTrack(
                              _selectedNode!.track!,
                            )
                          : null,
                    ),
                    ToolBarIconButton(
                      label: 'Zoom Out',
                      icon: MacosIcon(
                        CupertinoIcons.zoom_out,
                        color: MacosTheme.of(context).typography.body.color,
                      ),
                      showLabel: false,
                      tooltipMessage: 'Zoom Out',
                      onPressed: () => _homeManager.setZoom(
                        _homeManager.value.zoomLevel / 1.5,
                      ),
                    ),
                    ToolBarIconButton(
                      label: 'Zoom In',
                      icon: MacosIcon(
                        CupertinoIcons.zoom_in,
                        color: MacosTheme.of(context).typography.body.color,
                      ),
                      showLabel: false,
                      tooltipMessage: 'Zoom In',
                      onPressed: () => _homeManager.setZoom(
                        _homeManager.value.zoomLevel * 1.5,
                      ),
                    ),
                    const ToolBarSpacer(),
                    ToolBarIconButton(
                      label: 'Delete Track',
                      icon: const MacosIcon(
                        CupertinoIcons.trash,
                        color: CupertinoColors.destructiveRed,
                      ),
                      showLabel: false,
                      tooltipMessage: 'Delete Track',
                      onPressed: () => _deleteTrack(
                        _selectedNode!.track!,
                        _selectedNode!.collection!,
                      ),
                    ),
                  ]
                  // --- COLLECTION ACTIONS ---
                  else if (_selectedNode?.type == NodeType.collection) ...[
                    const ToolBarSpacer(),
                    ToolBarIconButton(
                      label: 'Delete Collection',
                      icon: const MacosIcon(
                        CupertinoIcons.trash,
                        color: CupertinoColors.destructiveRed,
                      ),
                      showLabel: true,
                      tooltipMessage: 'Delete Collection',
                      onPressed: () =>
                          _deleteCollection(_selectedNode!.collection!),
                    ),
                  ],
                ],
              ),
              children: [
                ContentArea(
                  builder: (context, scrollController) => _buildCenterPane(),
                ),
              ],
            ),
          );

    return PlatformMenuBar(menus: _buildMenus(), child: activeScreen);
  }
}
