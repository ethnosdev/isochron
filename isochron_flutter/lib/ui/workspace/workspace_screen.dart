import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:isochron_flutter/services/alignment_service.dart';
import 'package:isochron_flutter/ui/home_manager.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:isochron_cli/isochron_cli.dart';

import 'inspector_pane.dart';
import 'studio_editor.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  int _sidebarIndex = 1;
  bool _showInspector = true;

  Project? _project;
  AlignmentPair? _activePair;
  late final HomeManager _homeManager;
  final Uuid _uuid = const Uuid();

  // --- Batch State ---
  bool _isBatchRunning = false;
  String _batchStatus = "";
  double _batchProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _homeManager = HomeManager();
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
      _sidebarIndex = 1;
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
      for (var pair in _project!.alignments) {
        if (pair.audioAssetId == asset.id) pair.audioAssetId = null;
        if (pair.textAssetId == asset.id) pair.textAssetId = null;
        if (pair.dictAssetId == asset.id) pair.dictAssetId = null;
      }
    });
    _project!.save();
  }

  // ---------------------------------------------------------------------------
  // BATCH PROCESSING & EXPORT LOGIC
  // ---------------------------------------------------------------------------

  Future<void> _runBatch() async {
    if (_project == null) return;

    setState(() {
      _isBatchRunning = true;
      _batchStatus = "Starting Batch...";
      _batchProgress = 0.0;
    });

    final pendingPairs = _project!.alignments
        .where(
          (p) =>
              p.status == AlignmentStatus.pending ||
              p.status == AlignmentStatus.error,
        )
        .toList();

    final alignmentService = AlignmentService();

    for (var pair in pendingPairs) {
      if (!_isBatchRunning) break; // Check if user clicked Stop

      setState(() {
        pair.status = AlignmentStatus.processing;
        _batchStatus = "Processing ${pair.id}...";
      });

      final audioAsset = _project!.audioPool
          .where((a) => a.id == pair.audioAssetId)
          .firstOrNull;
      final textAsset = _project!.textPool
          .where((a) => a.id == pair.textAssetId)
          .firstOrNull;
      final dictAsset = _project!.dictPool
          .where((a) => a.id == pair.dictAssetId)
          .firstOrNull;

      if (audioAsset == null || textAsset == null) {
        setState(() {
          pair.status = AlignmentStatus.error;
        });
        continue; // Skip pairs missing files
      }

      File? tempCleanTextFile;
      List<String> extractedIds = [];
      String actualTextPath = textAsset.path;
      bool hasIds = pair.overrideHasIds ?? _project!.defaultHasIds;

      try {
        // Strip IDs if needed before alignment
        if (hasIds) {
          final lines = await File(textAsset.path).readAsLines();
          final cleanLines = <String>[];
          for (var line in lines) {
            if (line.trim().isEmpty) continue;
            final parts = line.trim().split(' ');
            if (parts.length > 1) {
              extractedIds.add(parts.first);
              cleanLines.add(parts.sublist(1).join(' '));
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

        // Run DSP Engine
        List<Fragment> fragments = await alignmentService.runIsochron(
          textPath: actualTextPath,
          audioPath: audioAsset.path,
          dictPath: dictAsset?.path,
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

        // Re-inject IDs
        if (hasIds && extractedIds.isNotEmpty) {
          for (int i = 0; i < fragments.length; i++) {
            if (i < extractedIds.length) {
              fragments[i] = fragments[i].copyWith(id: extractedIds[i]);
            }
          }
        }

        // Apply Auto-Generated IDs if needed
        if (!hasIds && _project!.defaultGenerateIds) {
          final prefix = _project!.defaultIdPrefix ?? "";
          int pairIdx = _project!.alignments.indexOf(pair) + 1;
          final recStr = pairIdx.toString().padLeft(3, '0');
          for (int j = 0; j < fragments.length; j++) {
            final verseStr = (j + 1).toString().padLeft(3, '0');
            fragments[j] = fragments[j].copyWith(id: '$prefix$recStr$verseStr');
          }
        }

        // Save Alignment Output
        final absPath = pair.getAbsoluteOutputPath(_project!.directoryPath);
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

        setState(() {
          pair.status = AlignmentStatus.done;
        });
      } catch (e) {
        debugPrint("Batch Error on ${pair.id}: $e");
        setState(() {
          pair.status = AlignmentStatus.error;
        });
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

  Future<void> _exportCsv() async {
    if (_project == null) return;

    final exportablePairs = _project!.alignments
        .where(
          (p) =>
              p.status == AlignmentStatus.done ||
              p.status == AlignmentStatus.reviewed,
        )
        .toList();

    if (exportablePairs.isEmpty) return;

    final String? outputFile = await FilePicker.saveFile(
      dialogTitle: 'Export Combined CSV',
      fileName: '${_project!.name.replaceAll(" ", "_")}_full.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (outputFile == null) return;

    try {
      final masterBuffer = StringBuffer();
      masterBuffer.writeln('id,verse_id,recording_id,start,end');

      for (var pair in exportablePairs) {
        final absJsonPath = pair.getAbsoluteOutputPath(_project!.directoryPath);
        final file = File(absJsonPath);

        if (await file.exists()) {
          final content = await file.readAsString();
          final List<dynamic> jsonList = jsonDecode(content);

          for (var j in jsonList) {
            masterBuffer.write('${j['index']},');
            masterBuffer.write('${j['id'] ?? ""},');
            masterBuffer.write('${pair.id},');
            masterBuffer.write('${j['start']},');
            masterBuffer.write('${j['end']}\n');
          }
        }
      }

      await File(outputFile).writeAsString(masterBuffer.toString());
    } catch (e) {
      debugPrint("CSV Export Error: $e");
    }
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
            label: _isBatchRunning ? 'Stop Batch' : 'Run All Pending',
            icon: MacosIcon(
              _isBatchRunning
                  ? CupertinoIcons.stop_fill
                  : CupertinoIcons.play_circle_fill,
              color: _isBatchRunning
                  ? CupertinoColors.destructiveRed
                  : CupertinoColors.activeGreen,
            ),
            showLabel: true,
            onPressed: _isBatchRunning
                ? () => setState(() => _isBatchRunning = false)
                : _runBatch,
          ),
        );
        actions.add(
          ToolBarIconButton(
            label: 'Export CSV',
            icon: const MacosIcon(CupertinoIcons.tray_arrow_down),
            showLabel: true,
            onPressed: _exportCsv,
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
            icon: const MacosIcon(CupertinoIcons.add),
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
        return _BatchProcessorView(
          pairs: _project!.alignments,
          isRunning: _isBatchRunning,
          status: _batchStatus,
          progress: _batchProgress,
        );
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
              _project!.save();
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
// UI COMPONENTS
// -----------------------------------------------------------------------------

class _BatchProcessorView extends StatelessWidget {
  final List<AlignmentPair> pairs;
  final bool isRunning;
  final String status;
  final double progress;

  const _BatchProcessorView({
    required this.pairs,
    required this.isRunning,
    required this.status,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (isRunning) ...[
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Text(status, style: MacosTheme.of(context).typography.headline),
                const SizedBox(height: 8),
                ProgressBar(value: progress * 100),
              ],
            ),
          ),
          Container(height: 1, color: MacosTheme.of(context).dividerColor),
        ],
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: pairs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final pair = pairs[i];
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: MacosTheme.of(context).canvasColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: CupertinoColors.systemGrey4),
                ),
                child: Row(
                  children: [
                    if (pair.status == AlignmentStatus.processing)
                      const ProgressCircle()
                    else
                      const MacosIcon(
                        CupertinoIcons.link,
                        color: CupertinoColors.systemGrey,
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        pair.id,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _getStatusColor(pair.status).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        pair.status.name.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          color: _getStatusColor(pair.status),
                        ),
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

  Color _getStatusColor(AlignmentStatus status) {
    switch (status) {
      case AlignmentStatus.done:
      case AlignmentStatus.reviewed:
        return CupertinoColors.activeGreen;
      case AlignmentStatus.processing:
        return CupertinoColors.activeBlue;
      case AlignmentStatus.error:
        return CupertinoColors.destructiveRed;
      case AlignmentStatus.pending:
      default:
        return CupertinoColors.systemYellow;
    }
  }
}

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
    if (pool.isEmpty) return Center(child: Text("No $type assets imported."));

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
    if (pairs.isEmpty)
      return const Center(
        child: Text(
          "Click the + icon in the toolbar to create an Alignment Pair.",
        ),
      );

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
