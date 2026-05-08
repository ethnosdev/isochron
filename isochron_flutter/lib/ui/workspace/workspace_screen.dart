import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:isochron_flutter/services/alignment_service.dart';
import 'package:isochron_flutter/services/audio_service.dart';
import 'package:isochron_flutter/services/export_service.dart';
import 'package:isochron_flutter/services/pins_service.dart';
import 'package:isochron_flutter/utils/id_extraction.dart';
import 'package:isochron_flutter/ui/app_manager.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:isochron_cli/isochron_cli.dart';

import 'studio_editor.dart';

// --- NODE ENUMS FOR SIDEBAR TREE ---
enum NodeType { collection, track, audio, text }

class TreeSelection {
  final NodeType type;
  final Collection collection;
  final Track? track;
  TreeSelection({required this.type, required this.collection, this.track});
}

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
  String? _editingNodeId;

  // Batch State
  bool _isBatchRunning = false;
  String _batchStatus = "";
  double _batchProgress = 0.0;

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
    final nameController = TextEditingController();
    final String? projectName = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Create New Project'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: CupertinoTextField(
            controller: nameController,
            placeholder: 'e.g. Gospel of John',
            autofocus: true,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: const Text('Next'),
          ),
        ],
      ),
    );

    if (projectName == null || projectName.isEmpty) return;

    final String? parentDir = await FilePicker.getDirectoryPath(
      dialogTitle: 'Select Where to Save Project',
    );
    if (parentDir == null) return;

    final projectDir = Directory(p.join(parentDir, projectName));
    if (await projectDir.exists()) {
      if (mounted) {
        showCupertinoDialog(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('Folder Already Exists'),
            content: Text('A folder named "$projectName" already exists.'),
            actions: [
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return;
    }

    await projectDir.create();
    await Directory(p.join(projectDir.path, 'alignments')).create();

    final newProject = Project(
      id: _uuid.v4(),
      name: projectName,
      directoryPath: projectDir.path,
    );
    // Auto-create initial collection
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
      final result = await FilePicker.pickFiles(
        dialogTitle: 'Open Project',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
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
  // INVALIDATION LOGIC (Used when replacing/editing text or audio)
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

    // Purge alignment data safely
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

      if (track.audioPath == null || track.textPath == null) {
        setState(() => track.status = AlignmentStatus.error);
        continue;
      }

      setState(() {
        track.status = AlignmentStatus.processing;
        _batchStatus = "Processing ${track.name}...";
      });

      File? tempCleanTextFile;
      List<String> extractedIds = [];
      String actualTextPath = track.textPath!;

      try {
        if (_project!.defaultHasIds) {
          final lines = await File(track.textPath!).readAsLines();
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
          audioPath: track.audioPath!,
          dictPath: _project!.dictPath,
          snapMode: _project!.snapMode,
          snapOffsetMs: _project!.snapOffset ?? 0,
          onProgress: (status, prog) {
            if (_isBatchRunning && mounted)
              setState(() {
                _batchStatus = status;
                _batchProgress = prog;
              });
          },
        );

        if (!_isBatchRunning) {
          setState(() => track.status = AlignmentStatus.pending);
          break;
        }

        if (_project!.defaultHasIds && extractedIds.isNotEmpty) {
          for (int i = 0; i < fragments.length; i++) {
            if (i < extractedIds.length)
              fragments[i] = fragments[i].copyWith(id: extractedIds[i]);
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

        final absPath = track.getAbsoluteOutputPath(_project!.directoryPath);
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
        if (tempCleanTextFile != null && await tempCleanTextFile.exists())
          await tempCleanTextFile.delete();
      }

      await _project!.save();
    }

    setState(() {
      _isBatchRunning = false;
      _batchStatus = "Batch Complete";
      _batchProgress = 1.0;
    });
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

  void _showProjectSettings() {
    showCupertinoDialog(
      context: context,
      builder: (context) {
        return _ProjectSettingsModal(
          project: _project!,
          onSaved: () => setState(() => _project!.save()),
        );
      },
    );
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
          iconColor: CupertinoColors.activeBlue,
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
            // If we are currently editing, clicking stops the edit without expanding/collapsing
            if (_editingNodeId != null) {
              setState(() => _editingNodeId = null);
              return;
            }
            if (await _requestCloseEditor()) {
              setState(() {
                if (_expandedNodes.contains(col.id))
                  _expandedNodes.remove(col.id);
                else
                  _expandedNodes.add(col.id);
                _selectedNode = TreeSelection(
                  type: NodeType.collection,
                  collection: col,
                );
              });
            }
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
              iconColor: _getTrackColor(track.status),
              isSelected: isTrackSelected,
              isExpanded: _expandedNodes.contains(track.id),
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
                if (await _requestCloseEditor()) {
                  setState(() {
                    _expandedNodes.add(track.id);
                    _selectedNode = TreeSelection(
                      type: NodeType.track,
                      collection: col,
                      track: track,
                    );
                  });
                  await _homeManager.loadTrack(track, _project!);
                }
              },
            ),
          );

          if (_expandedNodes.contains(track.id)) {
            // Audio Node
            final isAudioSelected =
                _selectedNode?.track == track &&
                _selectedNode?.type == NodeType.audio;
            rows.add(
              _buildTreeRow(
                label: track.audioPath != null
                    ? p.basename(track.audioPath!)
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
                  if (await _requestCloseEditor()) {
                    setState(
                      () => _selectedNode = TreeSelection(
                        type: NodeType.audio,
                        collection: col,
                        track: track,
                      ),
                    );
                  }
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
                    ? p.basename(track.textPath!)
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
                  if (await _requestCloseEditor()) {
                    setState(
                      () => _selectedNode = TreeSelection(
                        type: NodeType.text,
                        collection: col,
                        track: track,
                      ),
                    );
                  }
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
        padding: const EdgeInsets.all(16.0),
        child: Text(
          _project!.name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(height: 1, color: theme.dividerColor),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                MacosTooltip(
                  message: "Add Collection",
                  child: MacosIconButton(
                    icon: const MacosIcon(CupertinoIcons.folder_badge_plus),
                    onPressed: _addCollection,
                  ),
                ),
                MacosTooltip(
                  message: "Project Settings",
                  child: MacosIconButton(
                    icon: const MacosIcon(CupertinoIcons.settings),
                    onPressed: _showProjectSettings,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: rows,
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
                  ? _InlineTextEditor(
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

  Color _getTrackColor(AlignmentStatus status) {
    switch (status) {
      case AlignmentStatus.done:
      case AlignmentStatus.reviewed:
        return CupertinoColors.activeGreen;
      case AlignmentStatus.processing:
        return CupertinoColors.activeBlue;
      case AlignmentStatus.error:
        return CupertinoColors.destructiveRed;
      case AlignmentStatus.pending:
        return CupertinoColors.systemYellow;
    }
  }

  // ---------------------------------------------------------------------------
  // CENTER ROUTER
  // ---------------------------------------------------------------------------

  Widget _buildCenterPane() {
    if (_selectedNode == null)
      return const Center(child: Text("Select a collection or track."));

    switch (_selectedNode!.type) {
      case NodeType.collection:
        return _CollectionBatchView(
          collection: _selectedNode!.collection,
          project: _project!,
          isRunning: _isBatchRunning,
          status: _batchStatus,
          progress: _batchProgress,
          onRunBatch: () => _runBatch(_selectedNode!.collection),
          onStopBatch: () {
            setState(() => _isBatchRunning = false);
            _alignmentService.cancelCurrentRun();
          },
          onChanged: () {
            setState(() {}); // Synchronously update the UI first
            _project!.save(); // Then fire-and-forget the save to disk
          },
        );
      case NodeType.track:
        return StudioEditor(homeManager: _homeManager);
      case NodeType.text:
        return _TextEditorView(
          track: _selectedNode!.track!,
          onReplaceOrEdit: (action) =>
              _invalidateAndReplace(_selectedNode!.track!, action),
        );
      case NodeType.audio:
        return _AudioInspectorView(
          track: _selectedNode!.track!,
          onReplace: (action) =>
              _invalidateAndReplace(_selectedNode!.track!, action),
        );
    }
  }

  // ---------------------------------------------------------------------------
  // NATIVE MENU BAR & ROOT BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final Widget activeScreen = _project == null
        ? _buildWelcomeWindow()
        : MacosWindow(
            key: const ValueKey('main_workspace_window'), // <--- Added Key
            sidebar: _buildTreeSidebar(context),
            child: MacosScaffold(
              toolBar: ToolBar(
                title: Text(
                  _selectedNode?.type == NodeType.track
                      ? _selectedNode!.track!.name
                      : "Isochron Studio",
                ),
                actions: [
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

    // --- RESTORED NATIVE MACOS MENU BAR ---
    return PlatformMenuBar(
      menus: [
        const PlatformMenu(
          label: 'Isochron Studio',
          menus: [
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.about),
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
          ],
        ),
        PlatformMenu(
          label: 'File',
          menus: [
            // Group 1: Creating/Opening Projects
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
            // Group 2: Saving
            if (_project != null)
              PlatformMenuItemGroup(
                members: [
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
            // Group 3: Exporting
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
            // Group 4: Closing
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
      ],
      child: activeScreen,
    );
  }

  Widget _buildWelcomeWindow() {
    return MacosWindow(
      key: const ValueKey('welcome_window'), // <--- Added Key
      child: MacosScaffold(
        children: [
          ContentArea(
            builder: (context, scrollController) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const MacosIcon(
                    CupertinoIcons.waveform_path_ecg,
                    size: 80,
                    color: CupertinoColors.activeBlue,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    "Isochron Studio",
                    style: MacosTheme.of(context).typography.largeTitle
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 48),
                  PushButton(
                    controlSize: ControlSize.large,
                    onPressed: _createNewProject,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24.0),
                      child: Text("Create New Project"),
                    ),
                  ),
                  const SizedBox(height: 16),
                  PushButton(
                    controlSize: ControlSize.large,
                    secondary: true,
                    onPressed: _openProject,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24.0),
                      child: Text("Open Existing Project"),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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
    );
    if (outputFile == null) return;

    final payload = await ExportService.buildPhraseTiming(_project!, track);
    if (payload == null || payload.isEmpty) return;
    await File(outputFile).writeAsString(payload);
  }
}

// -----------------------------------------------------------------------------
// SUB-VIEWS
// -----------------------------------------------------------------------------

class _CollectionBatchView extends StatelessWidget {
  final Collection collection;
  final Project project;
  final bool isRunning;
  final String status;
  final double progress;
  final VoidCallback onRunBatch;
  final VoidCallback onStopBatch;
  final VoidCallback onChanged;

  const _CollectionBatchView({
    required this.collection,
    required this.project,
    required this.isRunning,
    required this.status,
    required this.progress,
    required this.onRunBatch,
    required this.onStopBatch,
    required this.onChanged,
  });

  Future<void> _importAndAutoPair() async {
    final result = await FilePicker.pickFiles(allowMultiple: true);
    if (result == null) return;

    final List<String> audioFiles = [];
    final List<String> textFiles = [];

    for (var file in result.files) {
      if (file.path == null) continue;
      final ext = p.extension(file.path!).toLowerCase();
      if (['.mp3', '.wav', '.m4a'].contains(ext)) {
        audioFiles.add(file.path!);
      } else if (['.txt', '.phrases'].contains(ext)) {
        textFiles.add(file.path!);
      }
    }

    if (audioFiles.isEmpty && textFiles.isEmpty) return;

    // Natural sort helper
    int naturalCompare(String a, String b) {
      final regex = RegExp(r'\d+|\D+');
      final matchesA = regex.allMatches(a).map((m) => m.group(0)!).toList();
      final matchesB = regex.allMatches(b).map((m) => m.group(0)!).toList();
      for (int i = 0; i < matchesA.length && i < matchesB.length; i++) {
        final isNumA = int.tryParse(matchesA[i]) != null;
        final isNumB = int.tryParse(matchesB[i]) != null;
        if (isNumA && isNumB) {
          final cmp = int.parse(matchesA[i]).compareTo(int.parse(matchesB[i]));
          if (cmp != 0) return cmp;
        } else {
          final cmp = matchesA[i].compareTo(matchesB[i]);
          if (cmp != 0) return cmp;
        }
      }
      return matchesA.length.compareTo(matchesB.length);
    }

    audioFiles.sort(naturalCompare);
    textFiles.sort(naturalCompare);

    // 1. FILL HOLES IN EXISTING TRACKS FIRST
    if (audioFiles.isNotEmpty) {
      final tracksNeedingAudio = collection.tracks
          .where((t) => t.audioPath == null)
          .toList();
      int fillCount = tracksNeedingAudio.length < audioFiles.length
          ? tracksNeedingAudio.length
          : audioFiles.length;
      for (int i = 0; i < fillCount; i++) {
        tracksNeedingAudio[i].audioPath = audioFiles.removeAt(0);
      }
    }

    if (textFiles.isNotEmpty) {
      final tracksNeedingText = collection.tracks
          .where((t) => t.textPath == null)
          .toList();
      int fillCount = tracksNeedingText.length < textFiles.length
          ? tracksNeedingText.length
          : textFiles.length;
      for (int i = 0; i < fillCount; i++) {
        tracksNeedingText[i].textPath = textFiles.removeAt(0);
      }
    }

    // 2. PAIR AND CREATE NEW TRACKS WITH WHATEVER IS LEFT OVER
    int maxCount = audioFiles.length > textFiles.length
        ? audioFiles.length
        : textFiles.length;
    for (int i = 0; i < maxCount; i++) {
      final audio = i < audioFiles.length ? audioFiles[i] : null;
      final text = i < textFiles.length ? textFiles[i] : null;

      final name = audio != null
          ? p.basenameWithoutExtension(audio)
          : p.basenameWithoutExtension(text!);

      collection.tracks.add(
        Track(
          id: const Uuid().v4(),
          name: name,
          audioPath: audio,
          textPath: text,
          outputFilename: '${name}_timing.json',
        ),
      );
    }

    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (collection.tracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MacosIcon(
              CupertinoIcons.tray_arrow_down,
              size: 64,
              color: CupertinoColors.systemGrey,
            ),
            const SizedBox(height: 16),
            Text(
              "Empty Collection",
              style: MacosTheme.of(context).typography.title1,
            ),
            const SizedBox(height: 8),
            const Text(
              "Select audio and text files to generate your tracks.",
              style: TextStyle(color: CupertinoColors.systemGrey),
            ),
            const SizedBox(height: 24),
            PushButton(
              controlSize: ControlSize.large,
              onPressed: _importAndAutoPair,
              child: const Text("Select Files..."),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              PushButton(
                controlSize: ControlSize.large,
                secondary: isRunning,
                onPressed: isRunning ? onStopBatch : onRunBatch,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MacosIcon(
                      isRunning
                          ? CupertinoIcons.stop_fill
                          : CupertinoIcons.play_arrow_solid,
                      size: 14,
                      color: isRunning
                          ? CupertinoColors.destructiveRed
                          : CupertinoColors.white,
                    ),
                    const SizedBox(width: 8),
                    Text(isRunning ? "Stop Batch" : "Run Alignment on All"),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // ADDED: Import button always available
              PushButton(
                controlSize: ControlSize.regular,
                secondary: true,
                onPressed: _importAndAutoPair,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MacosIcon(CupertinoIcons.add, size: 12),
                    SizedBox(width: 4),
                    Text("Import Files"),
                  ],
                ),
              ),
              const Spacer(),
              PushButton(
                controlSize: ControlSize.regular,
                secondary: true,
                onPressed: () async {
                  final out = await FilePicker.saveFile(
                    dialogTitle: 'Export CSV',
                    fileName: ExportService.defaultCsvFilename(project.name),
                    type: FileType.custom,
                    allowedExtensions: ['csv'],
                  );
                  if (out != null) {
                    final payload = await ExportService.buildCombinedCsv(
                      project,
                    );
                    await File(out).writeAsString(payload);
                  }
                },
                child: const Text("Export Combined CSV"),
              ),
            ],
          ),
        ),
        if (isRunning)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: ProgressBar(value: progress * 100),
          ),
        Container(height: 1, color: MacosTheme.of(context).dividerColor),
        Expanded(
          child: ListView.builder(
            itemCount: collection.tracks.length,
            itemExtent: 56,
            itemBuilder: (ctx, i) {
              final t = collection.tracks[i];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: MacosTheme.of(context).dividerColor,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    if (t.status == AlignmentStatus.processing)
                      const ProgressCircle()
                    else
                      const MacosIcon(
                        CupertinoIcons.waveform_path,
                        color: CupertinoColors.systemGrey,
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          if (t.audioPath == null || t.textPath == null)
                            Text(
                              t.audioPath == null
                                  ? "Missing Audio"
                                  : "Missing Text",
                              style: const TextStyle(
                                fontSize: 11,
                                color: CupertinoColors.destructiveRed,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      t.status.name.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: CupertinoColors.systemGrey,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TextEditorView extends StatefulWidget {
  final Track track;
  final Future<void> Function(Future<void> Function()) onReplaceOrEdit;
  const _TextEditorView({required this.track, required this.onReplaceOrEdit});

  @override
  State<_TextEditorView> createState() => _TextEditorViewState();
}

class _TextEditorViewState extends State<_TextEditorView> {
  late TextEditingController _controller;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _loadFile();
  }

  Future<void> _loadFile() async {
    if (widget.track.textPath != null &&
        await File(widget.track.textPath!).exists()) {
      _controller.text = await File(widget.track.textPath!).readAsString();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.track.textPath == null) {
      return Center(
        child: PushButton(
          controlSize: ControlSize.large,
          onPressed: () => _replaceFile(),
          child: const Text("Attach Text File"),
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: MacosTheme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              const MacosIcon(CupertinoIcons.doc_text),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.track.textPath!,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              if (_isEditing)
                PushButton(
                  controlSize: ControlSize.regular,
                  onPressed: () {
                    widget.onReplaceOrEdit(() async {
                      await File(
                        widget.track.textPath!,
                      ).writeAsString(_controller.text);
                      setState(() => _isEditing = false);
                    });
                  },
                  child: const Text("Save Edits"),
                ),
              const SizedBox(width: 8),
              PushButton(
                secondary: true,
                controlSize: ControlSize.regular,
                onPressed: _replaceFile,
                child: const Text("Replace File..."),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: MacosTextField(
              controller: _controller,
              maxLines: null,
              onChanged: (_) {
                if (!_isEditing) setState(() => _isEditing = true);
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _replaceFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'phrases'],
    );
    if (result != null && result.files.single.path != null) {
      widget.onReplaceOrEdit(() async {
        widget.track.textPath = result.files.single.path!;
        await _loadFile();
      });
    }
  }
}

class _AudioInspectorView extends StatefulWidget {
  final Track track;
  final Future<void> Function(Future<void> Function()) onReplace;
  const _AudioInspectorView({required this.track, required this.onReplace});

  @override
  State<_AudioInspectorView> createState() => _AudioInspectorViewState();
}

class _AudioInspectorViewState extends State<_AudioInspectorView> {
  final AudioService _audio = AudioService();
  bool _isPlaying = false;
  Duration? _duration;

  @override
  void initState() {
    super.initState();
    _initAudio();
    _audio.stateStream.listen((s) {
      if (mounted) setState(() => _isPlaying = s.playing);
    });
  }

  Future<void> _initAudio() async {
    if (widget.track.audioPath != null &&
        await File(widget.track.audioPath!).exists()) {
      _duration = await _audio.load(widget.track.audioPath!);
      setState(() {});
    }
  }

  @override
  void dispose() {
    _audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.track.audioPath == null) {
      return Center(
        child: PushButton(
          controlSize: ControlSize.large,
          onPressed: _replaceFile,
          child: const Text("Attach Audio File"),
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MacosIcon(
            CupertinoIcons.speaker_3_fill,
            size: 80,
            color: CupertinoColors.activeBlue,
          ),
          const SizedBox(height: 24),
          Text(
            p.basename(widget.track.audioPath!),
            style: MacosTheme.of(context).typography.title1,
          ),
          const SizedBox(height: 8),
          Text(
            _duration != null
                ? "${_duration!.inSeconds} seconds"
                : "Loading...",
            style: const TextStyle(color: CupertinoColors.systemGrey),
          ),
          const SizedBox(height: 32),
          MacosIconButton(
            icon: MacosIcon(
              _isPlaying
                  ? CupertinoIcons.pause_fill
                  : CupertinoIcons.play_arrow_solid,
              size: 24,
              color: CupertinoColors.white,
            ),
            backgroundColor: CupertinoColors.activeBlue,
            shape: BoxShape.circle,
            onPressed: () => _isPlaying ? _audio.pause() : _audio.play(),
          ),
          const SizedBox(height: 48),
          PushButton(
            secondary: true,
            controlSize: ControlSize.regular,
            onPressed: _replaceFile,
            child: const Text("Replace Audio File..."),
          ),
        ],
      ),
    );
  }

  Future<void> _replaceFile() async {
    final result = await FilePicker.pickFiles(type: FileType.audio);
    if (result != null && result.files.single.path != null) {
      widget.onReplace(() async {
        widget.track.audioPath = result.files.single.path!;
        await _initAudio();
      });
    }
  }
}

// -----------------------------------------------------------------------------
// PROJECT SETTINGS MODAL
// -----------------------------------------------------------------------------
class _ProjectSettingsModal extends StatefulWidget {
  final Project project;
  final VoidCallback onSaved;
  const _ProjectSettingsModal({required this.project, required this.onSaved});

  @override
  State<_ProjectSettingsModal> createState() => _ProjectSettingsModalState();
}

class _ProjectSettingsModalState extends State<_ProjectSettingsModal> {
  late bool _generateIds;
  late bool _hasIds;
  late String _prefix;

  @override
  void initState() {
    super.initState();
    _generateIds = widget.project.defaultGenerateIds;
    _hasIds = widget.project.defaultHasIds;
    _prefix = widget.project.defaultIdPrefix ?? "";
  }

  String get _idPreview {
    if (_generateIds)
      return "Preview: ID [${_prefix}001001] / Text [In the beginning...]";
    if (_hasIds) return "Preview: ID [40001001] / Text [In the beginning...]";
    return "Preview: ID [] / Text [In the beginning...]";
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: const Text("Project Settings"),
      content: Padding(
        padding: const EdgeInsets.only(top: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Verse ID Strategy",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: MacosPopupButton<int>(
                value: _generateIds ? 2 : (_hasIds ? 1 : 0),
                items: const [
                  MacosPopupMenuItem<int>(value: 0, child: Text('None')),
                  MacosPopupMenuItem<int>(
                    value: 1,
                    child: Text('IDs are in text file'),
                  ),
                  MacosPopupMenuItem<int>(
                    value: 2,
                    child: Text('Auto-Generate'),
                  ),
                ],
                onChanged: (val) {
                  setState(() {
                    if (val == 0) {
                      _hasIds = false;
                      _generateIds = false;
                    } else if (val == 1) {
                      _hasIds = true;
                      _generateIds = false;
                    } else if (val == 2) {
                      _hasIds = false;
                      _generateIds = true;
                    }
                  });
                },
              ),
            ),
            if (_generateIds) ...[
              const SizedBox(height: 8),
              MacosTextField(
                controller: TextEditingController(text: _prefix),
                placeholder: 'ID Prefix (e.g. 40)',
                onChanged: (val) => setState(() => _prefix = val),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              _idPreview,
              style: const TextStyle(
                fontSize: 11,
                color: CupertinoColors.systemGrey,
                fontStyle: FontStyle.italic,
              ),
            ),

            const SizedBox(height: 16),
            const Text(
              "Snap Mode",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: MacosPopupButton<String>(
                value: widget.project.snapMode,
                items: const [
                  MacosPopupMenuItem<String>(
                    value: 'onset',
                    child: Text('Onset (Phrase start)'),
                  ),
                  MacosPopupMenuItem<String>(
                    value: 'gap',
                    child: Text('Gap (Silence between)'),
                  ),
                ],
                onChanged: (val) {
                  if (val != null)
                    setState(() => widget.project.snapMode = val);
                },
              ),
            ),

            const SizedBox(height: 16),
            const Text(
              "Global Transliteration Dict",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.project.dictPath != null
                        ? p.basename(widget.project.dictPath!)
                        : "None",
                    maxLines: 1,
                  ),
                ),
                PushButton(
                  controlSize: ControlSize.small,
                  secondary: true,
                  onPressed: () async {
                    final res = await FilePicker.pickFiles(
                      allowedExtensions: ['json'],
                      type: FileType.custom,
                    );
                    if (res != null)
                      setState(
                        () => widget.project.dictPath = res.files.single.path!,
                      );
                  },
                  child: const Text("Select"),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () {
            widget.project.defaultGenerateIds = _generateIds;
            widget.project.defaultHasIds = _hasIds;
            widget.project.defaultIdPrefix = _prefix;
            widget.onSaved();
            Navigator.pop(context);
          },
          child: const Text("Save"),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// INLINE TREE EDITOR
// -----------------------------------------------------------------------------
class _InlineTextEditor extends StatefulWidget {
  final String initialText;
  final ValueChanged<String> onComplete;

  const _InlineTextEditor({
    required this.initialText,
    required this.onComplete,
  });

  @override
  State<_InlineTextEditor> createState() => _InlineTextEditorState();
}

class _InlineTextEditorState extends State<_InlineTextEditor> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _focusNode = FocusNode();

    // Save when focus is lost (clicking elsewhere)
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        widget.onComplete(_controller.text);
      }
    });

    // Auto focus the text field immediately when it appears
    Future.microtask(() {
      if (mounted) {
        _focusNode.requestFocus();
        // Highlight all text so typing immediately overwrites it
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MacosTextField(
      controller: _controller,
      focusNode: _focusNode,
      maxLines: 1,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      style: const TextStyle(fontSize: 13),
      // Save when hitting Enter
      onSubmitted: widget.onComplete,
    );
  }
}
