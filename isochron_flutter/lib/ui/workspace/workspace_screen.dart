import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'; // For some layout widgets
import 'package:isochron_flutter/ui/home_manager.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'inspector_pane.dart';
import 'studio_editor.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  int _sidebarIndex = 1; // Default to Alignments
  bool _showInspector = true;

  Project? _project;
  AlignmentPair? _activePair;
  late final HomeManager _homeManager;
  final Uuid _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    _homeManager = HomeManager();
    // In Phase 3, we hooked up a save callback. Let's make sure saving the alignment
    // also saves the project state (e.g. updating the status to "done").
    _homeManager.onSaveCallback = () {
      if (_activePair != null) {
        setState(() => _activePair!.status = AlignmentStatus.reviewed);
        _project?.save();
      }
    };
  }

  @override
  void dispose() {
    _homeManager.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // PROJECT MANAGEMENT LOGIC
  // ---------------------------------------------------------------------------

  Future<void> _createNewProject() async {
    final String? dir = await FilePicker.getDirectoryPath(
      dialogTitle: 'Select Folder for New Project',
    );
    if (dir == null) return;

    final alignmentsDir = Directory(p.join(dir, 'alignments'));
    if (!await alignmentsDir.exists()) {
      await alignmentsDir.create();
    }

    final newProject = Project(
      id: _uuid.v4(),
      name: p.basename(dir),
      directoryPath: dir,
    );
    await newProject.save();

    setState(() {
      _project = newProject;
      _sidebarIndex = 1; // Go to alignments
    });
  }

  Future<void> _openProject() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Open Project',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result != null && result.files.single.path != null) {
      try {
        final file = File(result.files.single.path!);
        final content = await file.readAsString();
        final jsonMap = jsonDecode(content);

        setState(() {
          _project = Project.fromJson(jsonMap);
          _sidebarIndex = 1;
        });
      } catch (e) {
        debugPrint("Error loading project: $e");
      }
    }
  }

  // ---------------------------------------------------------------------------
  // ASSET & PAIR MANAGEMENT
  // ---------------------------------------------------------------------------

  Future<void> _importAsset(
    String type,
    List<String>? extensions,
    List<ProjectAsset> targetPool,
  ) async {
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      type: extensions != null ? FileType.custom : FileType.audio,
      allowedExtensions: extensions,
    );

    if (result != null && _project != null) {
      setState(() {
        for (var file in result.files) {
          if (file.path != null) {
            targetPool.add(ProjectAsset(id: _uuid.v4(), path: file.path!));
          }
        }
      });
      await _project!.save();
    }
  }

  void _createNewPair() {
    if (_project == null) return;
    setState(() {
      final pairCount = _project!.alignments.length + 1;
      _project!.alignments.add(
        AlignmentPair(
          id: 'Pair ${pairCount.toString().padLeft(2, '0')}',
          outputFilename: 'alignment_$pairCount.json',
        ),
      );
    });
    _project!.save();
  }

  void _deletePair(AlignmentPair pair) {
    if (_project == null) return;
    setState(() {
      if (_activePair == pair) _activePair = null;
      _project!.alignments.remove(pair);
    });
    _project!.save();
  }

  void _deleteAsset(ProjectAsset asset, List<ProjectAsset> pool) {
    if (_project == null) return;
    setState(() {
      pool.remove(asset);
      // Orphan any pairs that used this asset
      for (var pair in _project!.alignments) {
        if (pair.audioAssetId == asset.id) pair.audioAssetId = null;
        if (pair.textAssetId == asset.id) pair.textAssetId = null;
        if (pair.dictAssetId == asset.id) pair.dictAssetId = null;
      }
    });
    _project!.save();
  }

  // ---------------------------------------------------------------------------
  // UI BUILDERS
  // ---------------------------------------------------------------------------

  ToolBar _buildToolBar(BuildContext context) {
    if (_activePair != null) {
      return ToolBar(
        title: Text(_activePair!.id),
        titleWidth: 200.0,
        leading: MacosTooltip(
          message: 'Close Editor',
          useMousePosition: false,
          child: MacosIconButton(
            icon: const MacosIcon(CupertinoIcons.chevron_left),
            onPressed: () => setState(() => _activePair = null),
          ),
        ),
        actions: [
          ToolBarIconButton(
            label: 'Auto-Align',
            icon: const MacosIcon(CupertinoIcons.wand_rays),
            showLabel: true,
            onPressed: () => _homeManager.runAlignment(
              context,
              snapMode: _project!.snapMode,
              snapOffsetMs: _project!.snapOffset ?? 0,
            ),
          ),
          const ToolBarSpacer(),
          ToolBarIconButton(
            label: 'Toggle Inspector',
            icon: const MacosIcon(CupertinoIcons.sidebar_right),
            showLabel: false,
            onPressed: () => setState(() => _showInspector = !_showInspector),
          ),
        ],
      );
    }

    String title = [
      "Batch Processor",
      "Alignments",
      "Audio Pool",
      "Text Pool",
      "Dictionaries",
    ][_sidebarIndex];
    List<ToolbarItem> actions = [];

    switch (_sidebarIndex) {
      case 0:
        actions.add(
          ToolBarIconButton(
            label: 'Run All Pending',
            icon: const MacosIcon(
              CupertinoIcons.play_circle_fill,
              color: CupertinoColors.activeGreen,
            ),
            showLabel: true,
            onPressed: () {}, // Future Batch Logic
          ),
        );
        break;
      case 1:
        actions.add(
          ToolBarIconButton(
            label: 'Create New Pair',
            icon: const MacosIcon(CupertinoIcons.add),
            showLabel: true,
            onPressed: _createNewPair,
          ),
        );
        break;
      case 2:
        actions.add(
          ToolBarIconButton(
            label: 'Import Audio',
            icon: const MacosIcon(CupertinoIcons.folder_badge_plus),
            showLabel: true,
            onPressed: () => _importAsset('Audio', null, _project!.audioPool),
          ),
        );
        break;
      case 3:
        actions.add(
          ToolBarIconButton(
            label: 'Import Text',
            icon: MacosIcon(CupertinoIcons.add),
            showLabel: true,
            onPressed: () => _importAsset('Text', ['txt'], _project!.textPool),
          ),
        );
        break;
      case 4:
        actions.add(
          ToolBarIconButton(
            label: 'Import Dict',
            icon: const MacosIcon(CupertinoIcons.book_circle),
            showLabel: true,
            onPressed: () => _importAsset('Dict', ['json'], _project!.dictPool),
          ),
        );
        break;
    }

    return ToolBar(
      title: Text(title),
      titleWidth: 200.0,
      leading: MacosTooltip(
        message: 'Toggle Sidebar',
        useMousePosition: false,
        child: MacosIconButton(
          icon: const MacosIcon(CupertinoIcons.sidebar_left),
          onPressed: () => MacosWindowScope.of(context).toggleSidebar(),
        ),
      ),
      actions: [
        ...actions,
        const ToolBarSpacer(),
        ToolBarIconButton(
          label: 'Toggle Inspector',
          icon: const MacosIcon(CupertinoIcons.sidebar_right),
          showLabel: false,
          onPressed: () => setState(() => _showInspector = !_showInspector),
        ),
      ],
    );
  }

  Widget _buildCenterPane() {
    if (_activePair != null) {
      return StudioEditor(homeManager: _homeManager);
    }

    switch (_sidebarIndex) {
      case 0:
        return const Center(child: Text("Batch Processor (Coming Soon)"));
      case 1:
        return _RealAlignmentList(
          pairs: _project!.alignments,
          onOpenPair: (pair) async {
            setState(() => _activePair = pair);
            await _homeManager.loadAlignmentPair(pair, _project!);
          },
          onDelete: _deletePair,
        );
      case 2:
        return _RealAssetPool(
          type: "Audio",
          pool: _project!.audioPool,
          onDelete: (a) => _deleteAsset(a, _project!.audioPool),
        );
      case 3:
        return _RealAssetPool(
          type: "Text",
          pool: _project!.textPool,
          onDelete: (a) => _deleteAsset(a, _project!.textPool),
        );
      case 4:
        return _RealAssetPool(
          type: "Dictionaries",
          pool: _project!.dictPool,
          onDelete: (a) => _deleteAsset(a, _project!.dictPool),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    // -------------------------------------------------------------------------
    // WELCOME SCREEN (No Project Loaded)
    // -------------------------------------------------------------------------
    if (_project == null) {
      return MacosWindow(
        key: const ValueKey('welcome_window'),
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
                    const SizedBox(height: 8),
                    Text(
                      "Synthesis-Based Forced Aligner",
                      style: MacosTheme.of(context).typography.title3.copyWith(
                        color: CupertinoColors.systemGrey,
                      ),
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

    // -------------------------------------------------------------------------
    // MAIN WORKSPACE (Project Loaded)
    // -------------------------------------------------------------------------
    return MacosWindow(
      key: const ValueKey('main_workspace_window'),
      sidebar: Sidebar(
        minWidth: 200,
        bottom: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _project!.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const Text(
                'Isochron Studio v1.0',
                style: TextStyle(
                  fontSize: 11,
                  color: CupertinoColors.systemGrey,
                ),
              ),
              const SizedBox(height: 8),
              PushButton(
                controlSize: ControlSize.small,
                secondary: true,
                onPressed: () => setState(() => _project = null),
                child: const Text("Close Project"),
              ),
            ],
          ),
        ),
        builder: (context, scrollController) {
          return SidebarItems(
            currentIndex: _sidebarIndex,
            onChanged: (i) {
              setState(() {
                _sidebarIndex = i;
                _activePair = null;
              });
            },
            scrollController: scrollController,
            items: const [
              SidebarItem(
                leading: MacosIcon(CupertinoIcons.rectangle_grid_1x2),
                label: Text('Batch Processor'),
              ),
              SidebarItem(
                leading: MacosIcon(CupertinoIcons.waveform_path),
                label: Text('Alignments'),
              ),
              SidebarItem(
                leading: MacosIcon(CupertinoIcons.folder),
                label: Text('Audio Pool'),
              ),
              SidebarItem(
                leading: MacosIcon(CupertinoIcons.doc_text),
                label: Text('Text Pool'),
              ),
              SidebarItem(
                leading: MacosIcon(CupertinoIcons.book),
                label: Text('Dictionaries'),
              ),
            ],
          );
        },
      ),
      endSidebar: Sidebar(
        startWidth: 260,
        minWidth: 200,
        maxWidth: 300,
        shownByDefault: _showInspector,
        builder: (context, scrollController) {
          return InspectorPane(
            project: _project!,
            activePair: _activePair,
            onChanged: () {
              setState(() {});
              _project!.save(); // Save properties when inspector changes
            },
          );
        },
      ),
      child: MacosScaffold(
        toolBar: _buildToolBar(context),
        children: [
          ContentArea(
            builder: (context, scrollController) => _buildCenterPane(),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// REAL UI COMPONENTS FOR ASSETS AND ALIGNMENTS
// -----------------------------------------------------------------------------

class _RealAssetPool extends StatelessWidget {
  final String type;
  final List<ProjectAsset> pool;
  final Function(ProjectAsset) onDelete;

  const _RealAssetPool({
    required this.type,
    required this.pool,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (pool.isEmpty) {
      return Center(child: Text("No $type assets imported."));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: pool.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final asset = pool[i];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: MacosTheme.of(context).canvasColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: CupertinoColors.systemGrey4),
          ),
          child: Row(
            children: [
              MacosIcon(
                type == "Audio"
                    ? CupertinoIcons.waveform
                    : CupertinoIcons.doc_text,
                color: CupertinoColors.systemGrey,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      asset.filename,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      asset.path,
                      style: MacosTheme.of(context).typography.footnote
                          .copyWith(color: CupertinoColors.systemGrey),
                    ),
                  ],
                ),
              ),
              MacosIconButton(
                icon: const MacosIcon(
                  CupertinoIcons.trash,
                  color: CupertinoColors.destructiveRed,
                ),
                onPressed: () => onDelete(asset),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RealAlignmentList extends StatelessWidget {
  final List<AlignmentPair> pairs;
  final Function(AlignmentPair) onOpenPair;
  final Function(AlignmentPair) onDelete;

  const _RealAlignmentList({
    required this.pairs,
    required this.onOpenPair,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (pairs.isEmpty) {
      return const Center(
        child: Text(
          "Click the + icon in the toolbar to create an Alignment Pair.",
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: pairs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final pair = pairs[i];
        final bool isReady =
            pair.audioAssetId != null && pair.textAssetId != null;

        return GestureDetector(
          onDoubleTap: () {
            if (isReady) onOpenPair(pair);
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: MacosTheme.of(context).canvasColor,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: CupertinoColors.systemGrey4),
            ),
            child: Row(
              children: [
                const MacosIcon(
                  CupertinoIcons.link,
                  color: CupertinoColors.systemGrey,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pair.id,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (!isReady)
                        Text(
                          "Missing Audio or Text. Select in Inspector.",
                          style: MacosTheme.of(context).typography.footnote
                              .copyWith(color: CupertinoColors.destructiveRed),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: pair.status == AlignmentStatus.reviewed
                        ? CupertinoColors.activeGreen.withOpacity(0.2)
                        : CupertinoColors.systemYellow.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    pair.status.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      color: pair.status == AlignmentStatus.reviewed
                          ? CupertinoColors.activeGreen
                          : CupertinoColors.systemYellow,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                MacosIconButton(
                  icon: const MacosIcon(
                    CupertinoIcons.trash,
                    color: CupertinoColors.destructiveRed,
                  ),
                  onPressed: () => onDelete(pair),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
