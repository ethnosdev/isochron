import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:isochron_flutter/services/alignment_service.dart';
import 'package:isochron_flutter/ui/app_manager.dart';
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
  bool _isSidebarCollapsed = false;

  Project? _project;
  AlignmentPair? _activePair;
  AlignmentPair? _selectedPair;
  late final AppManager _homeManager;
  final Uuid _uuid = const Uuid();
  bool _hasUnsavedChanges = false;
  final _alignmentService = AlignmentService();

  // --- Batch State ---
  bool _isBatchRunning = false;
  String _batchStatus = "";
  double _batchProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _homeManager = AppManager();
    _homeManager.onSaveCallback = () {
      if (_activePair != null) {
        setState(() => _activePair!.status = AlignmentStatus.reviewed);
        _project?.save();
      }
    };
    _homeManager.addListener(() {
      if (_homeManager.value.hasUnsavedChanges != _hasUnsavedChanges) {
        setState(() {
          _hasUnsavedChanges = _homeManager.value.hasUnsavedChanges;
        });
      }
    });
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
    // STEP 1: Ask the user for the Project Name
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
            onPressed: () {
              if (nameController.text.trim().isNotEmpty) {
                Navigator.pop(context, nameController.text.trim());
              }
            },
            child: const Text('Next'),
          ),
        ],
      ),
    );

    if (projectName == null || projectName.isEmpty) return;

    // STEP 2: Ask where to save it
    final String? parentDir = await FilePicker.getDirectoryPath(
      dialogTitle: 'Select Where to Save Project',
    );
    if (parentDir == null) return;

    // STEP 3: Create the project folder automatically
    final projectDir = Directory(p.join(parentDir, projectName));

    // Safety check: Does it already exist?
    if (await projectDir.exists()) {
      if (mounted) {
        showCupertinoDialog(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('Folder Already Exists'),
            content: Text(
              'A folder named "$projectName" already exists in this location.',
            ),
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

    // Create directories
    await projectDir.create();
    final alignmentsDir = Directory(p.join(projectDir.path, 'alignments'));
    await alignmentsDir.create();

    // Create and save project
    final newProject = Project(
      id: _uuid.v4(),
      name: projectName,
      directoryPath: projectDir.path,
    );
    await newProject.save();

    setState(() {
      _project = newProject;
      _sidebarIndex = 1;
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
        final file = File(result.files.single.path!);
        final content = await file.readAsString();
        final dynamic parsed = jsonDecode(content);

        if (parsed is! Map<String, dynamic>) {
          throw const FormatException("Invalid project file format.");
        }

        setState(() {
          _project = Project.fromJson(parsed);
          _sidebarIndex = 1;
        });
      }
    } catch (e, stackTrace) {
      debugPrint("Error loading project: $e\n$stackTrace");
      if (mounted) {
        showCupertinoDialog(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('Failed to Open Project'),
            content: Text(e.toString()),
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

  Future<void> _autoGeneratePairs() async {
    if (_project == null) return;

    // 1. Find assets that are NOT currently used in any alignment pair
    final usedAudioIds = _project!.alignments
        .map((p) => p.audioAssetId)
        .toSet();
    final usedTextIds = _project!.alignments.map((p) => p.textAssetId).toSet();

    final unlinkedAudio = _project!.audioPool
        .where((a) => !usedAudioIds.contains(a.id))
        .toList();
    final unlinkedText = _project!.textPool
        .where((t) => !usedTextIds.contains(t.id))
        .toList();

    if (unlinkedAudio.isEmpty || unlinkedText.isEmpty) {
      showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Nothing to Pair'),
          content: const Text(
            'You need both unlinked Audio and unlinked Text assets in your pools to generate pairs.',
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    // 2. Natural Sort Helper (makes "file_2" come before "file_10")
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

    // 3. Sort both lists naturally by filename
    unlinkedAudio.sort((a, b) => naturalCompare(a.filename, b.filename));
    unlinkedText.sort((a, b) => naturalCompare(a.filename, b.filename));

    // 4. Determine how many pairs we can make
    final int pairsToMake = unlinkedAudio.length < unlinkedText.length
        ? unlinkedAudio.length
        : unlinkedText.length;

    // 5. Ask for confirmation
    final bool? confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Auto-Generate Pairs'),
        content: Text(
          'Found unlinked assets. This will sequentially link them and create $pairsToMake new pairs.\n\nDo you want to continue?',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Generate'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // 6. Generate the pairs
    setState(() {
      final startingCount = _project!.alignments.length;
      for (int i = 0; i < pairsToMake; i++) {
        final pairCount = startingCount + i + 1;
        _project!.alignments.add(
          AlignmentPair(
            id: 'Pair ${pairCount.toString().padLeft(2, '0')}',
            audioAssetId: unlinkedAudio[i].id,
            textAssetId: unlinkedText[i].id,
            outputFilename: 'alignment_$pairCount.json',
          ),
        );
      }
    });
    _project!.save();
  }

  void _deletePair(AlignmentPair pair) {
    if (_project == null) return;
    setState(() {
      if (_activePair == pair) _activePair = null;
      if (_selectedPair == pair) _selectedPair = null;
      _project!.alignments.remove(pair);
    });
    _project!.save();
  }

  void _deleteAsset(ProjectAsset asset, List<ProjectAsset> pool) {
    if (_project == null) return;
    setState(() {
      pool.remove(asset);

      // If they deleted the active project dictionary, clear it
      if (_project!.dictAssetId == asset.id) {
        _project!.dictAssetId = null;
      }

      // Clear from pairs (dictAssetId is no longer in pairs)
      for (var pair in _project!.alignments) {
        if (pair.audioAssetId == asset.id) pair.audioAssetId = null;
        if (pair.textAssetId == asset.id) pair.textAssetId = null;
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
          .where((a) => a.id == _project!.dictAssetId)
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

        // Run DSP Engine using the class-level _alignmentService
        List<Fragment> fragments = await _alignmentService.runIsochron(
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

        // INSTANT CANCEL CHECK: If the user hit stop during processing
        if (!_isBatchRunning) {
          setState(() => pair.status = AlignmentStatus.pending);
          break; // Break the loop so it doesn't save corrupt/empty data
        }

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
        // If it throws an error because it was killed, safely ignore it.
        if (!_isBatchRunning) {
          setState(() => pair.status = AlignmentStatus.pending);
          break;
        } else {
          debugPrint("Batch Error on ${pair.id}: $e");
          setState(() {
            pair.status = AlignmentStatus.error;
          });
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

  Future<bool> _requestCloseEditor() async {
    if (_activePair != null && _homeManager.value.hasUnsavedChanges) {
      final result = await showCupertinoDialog<String>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Unsaved Changes'),
          content: const Text(
            'You have unsaved changes in your alignment. Do you want to save them before leaving?',
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
        return false; // User cancelled the navigation
      }
    }
    return true; // No unsaved changes, safe to close
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
            onPressed: () async {
              if (await _requestCloseEditor()) {
                setState(() => _activePair = null);
              }
            },
          ),
        ),
        actions: [
          ToolBarIconButton(
            label: 'Save',
            icon: MacosIcon(
              CupertinoIcons.floppy_disk,
              color: _hasUnsavedChanges
                  ? MacosTheme.of(context).typography.body.color
                  : CupertinoColors.systemGrey.withValues(alpha: 0.5),
            ),
            showLabel: true,
            tooltipMessage: 'Save Alignment (Cmd + S)',
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
          const ToolBarSpacer(),
          CustomToolbarItem(
            inToolbarBuilder: (context) => MacosTooltip(
              message: 'Toggle Sidebar',
              useMousePosition: false,
              child: MacosIconButton(
                icon: const MacosIcon(CupertinoIcons.sidebar_left),
                onPressed: () =>
                    setState(() => _isSidebarCollapsed = !_isSidebarCollapsed),
              ),
            ),
          ),

          CustomToolbarItem(
            inToolbarBuilder: (context) => MacosTooltip(
              message: 'Toggle Inspector',
              useMousePosition: false,
              child: MacosIconButton(
                icon: const MacosIcon(CupertinoIcons.sidebar_right),
                onPressed: () =>
                    MacosWindowScope.of(context).toggleEndSidebar(),
              ),
            ),
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
                ? () {
                    setState(() => _isBatchRunning = false);
                    _alignmentService.cancelCurrentRun();
                  }
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
        actions.add(
          ToolBarIconButton(
            label: 'Auto-Pair Unlinked',
            icon: MacosIcon(CupertinoIcons.link),
            showLabel: true,
            onPressed: _autoGeneratePairs,
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
      actions: [
        ...actions,
        const ToolBarSpacer(),
        CustomToolbarItem(
          inToolbarBuilder: (context) => MacosTooltip(
            message: 'Toggle Sidebar',
            useMousePosition: false,
            child: MacosIconButton(
              icon: const MacosIcon(CupertinoIcons.sidebar_left),
              onPressed: () =>
                  setState(() => _isSidebarCollapsed = !_isSidebarCollapsed),
            ),
          ),
        ),

        CustomToolbarItem(
          inToolbarBuilder: (context) => MacosTooltip(
            message: 'Toggle Inspector',
            useMousePosition: false,
            child: MacosIconButton(
              icon: const MacosIcon(CupertinoIcons.sidebar_right),
              onPressed: () => MacosWindowScope.of(context).toggleEndSidebar(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCenterPane(BuildContext context) {
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
          selectedPair: _selectedPair,
          onSelect: (pair) {
            setState(() {
              _selectedPair = pair;
            });
            // Auto-open inspector if it's currently hidden
            if (!MacosWindowScope.of(context).isEndSidebarShown) {
              MacosWindowScope.of(context).toggleEndSidebar();
            }
          },
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

  // ---------------------------------------------------------------------------
  // BUILD HELPERS
  // ---------------------------------------------------------------------------

  Widget _buildWelcomeWindow(BuildContext context) {
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

  Widget _buildMainWindow(BuildContext context) {
    return MacosWindow(
      key: const ValueKey('main_workspace_window'),
      sidebar: Sidebar(
        minWidth: _isSidebarCollapsed ? 90 : 200,
        startWidth: _isSidebarCollapsed ? 90 : 200,
        maxWidth: _isSidebarCollapsed ? 90 : 300,
        top: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            mainAxisAlignment: _isSidebarCollapsed
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              const MacosIcon(
                CupertinoIcons.folder_solid,
                color: CupertinoColors.activeBlue,
              ),
              if (!_isSidebarCollapsed) ...[
                const SizedBox(width: 8),
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
              ],
            ],
          ),
        ),
        builder: (context, scrollController) {
          return SidebarItems(
            selectedColor: CupertinoColors.systemBlue
                .resolveFrom(context)
                .withValues(alpha: 0.15),
            currentIndex: _sidebarIndex,
            onChanged: (i) async {
              if (i == _sidebarIndex) return;

              if (await _requestCloseEditor()) {
                setState(() {
                  _sidebarIndex = i;
                  _activePair = null;
                  _selectedPair = null;
                });
              }
            },
            scrollController: scrollController,
            items: [
              SidebarItem(
                leading: _isSidebarCollapsed
                    ? null
                    : const MacosIcon(CupertinoIcons.rectangle_grid_1x2),
                label: _isSidebarCollapsed
                    ? Container(
                        width: double.infinity,
                        alignment: Alignment.center,
                        child: const MacosIcon(
                          CupertinoIcons.rectangle_grid_1x2,
                          size: 16,
                        ),
                      )
                    : const Text('Batch Processor'),
              ),
              SidebarItem(
                leading: _isSidebarCollapsed
                    ? null
                    : const MacosIcon(CupertinoIcons.waveform_path),
                label: _isSidebarCollapsed
                    ? Container(
                        width: double.infinity,
                        alignment: Alignment.center,
                        child: const MacosIcon(
                          CupertinoIcons.waveform_path,
                          size: 16,
                        ),
                      )
                    : const Text('Alignments'),
              ),
              SidebarItem(
                leading: _isSidebarCollapsed
                    ? null
                    : const MacosIcon(CupertinoIcons.folder),
                label: _isSidebarCollapsed
                    ? Container(
                        width: double.infinity,
                        alignment: Alignment.center,
                        child: const MacosIcon(CupertinoIcons.folder, size: 16),
                      )
                    : const Text('Audio Pool'),
              ),
              SidebarItem(
                leading: _isSidebarCollapsed
                    ? null
                    : const MacosIcon(CupertinoIcons.doc_text),
                label: _isSidebarCollapsed
                    ? Container(
                        width: double.infinity,
                        alignment: Alignment.center,
                        child: const MacosIcon(
                          CupertinoIcons.doc_text,
                          size: 16,
                        ),
                      )
                    : const Text('Text Pool'),
              ),
              SidebarItem(
                leading: _isSidebarCollapsed
                    ? null
                    : const MacosIcon(CupertinoIcons.book),
                label: _isSidebarCollapsed
                    ? Container(
                        width: double.infinity,
                        alignment: Alignment.center,
                        child: const MacosIcon(CupertinoIcons.book, size: 16),
                      )
                    : const Text('Dictionaries'),
              ),
            ],
          );
        },
      ),
      endSidebar: Sidebar(
        startWidth: 260,
        minWidth: 200,
        maxWidth: 300,
        builder: (context, scrollController) {
          return InspectorPane(
            project: _project!,
            activePair: _activePair ?? _selectedPair,
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
            builder: (context, scrollController) => _buildCenterPane(context),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget activeScreen = _project == null
        ? _buildWelcomeWindow(context)
        : _buildMainWindow(context);

    // --- NATIVE MACOS MENU BAR ---
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
                    onSelected: (_activePair != null && !_hasUnsavedChanges)
                        ? null // Disabled if editing but no changes
                        : () {
                            if (_activePair != null) {
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
                    onSelected: _exportCsv,
                  ),
                ],
              ),
            // Group 3: Closing (Flutter automatically adds a divider above this group)
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
                        setState(() => _project = null);
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
}

// -----------------------------------------------------------------------------
// UI COMPONENTS
// -----------------------------------------------------------------------------

class _BatchProcessorView extends StatefulWidget {
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
  State<_BatchProcessorView> createState() => _BatchProcessorViewState();
}

class _BatchProcessorViewState extends State<_BatchProcessorView> {
  AlignmentPair? _selectedPair;

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);

    return Column(
      children: [
        if (widget.isRunning) ...[
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Text(widget.status, style: theme.typography.headline),
                const SizedBox(height: 8),
                ProgressBar(value: widget.progress * 100),
              ],
            ),
          ),
          Container(height: 1, color: theme.dividerColor),
        ],
        Expanded(
          child: ListView.builder(
            itemCount: widget.pairs.length,
            itemExtent: 56.0,
            itemBuilder: (context, i) {
              final pair = widget.pairs[i];
              final isSelected = _selectedPair == pair;

              final macBlue = CupertinoColors.systemBlue.resolveFrom(context);
              final bgColor = isSelected
                  ? macBlue.withValues(alpha: 0.15)
                  : CupertinoColors.transparent;
              final textColor = theme.typography.body.color;
              final iconColor = isSelected
                  ? macBlue
                  : CupertinoColors.systemGrey;

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _selectedPair = pair),
                child: Container(
                  height: 56.0,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: bgColor,
                    border: Border(
                      bottom: BorderSide(color: theme.dividerColor),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (pair.status == AlignmentStatus.processing)
                        const ProgressCircle()
                      else
                        MacosIcon(CupertinoIcons.link, color: iconColor),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          pair.id,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? macBlue.withValues(alpha: 0.15)
                              : _getStatusColor(
                                  pair.status,
                                ).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          pair.status.name.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? macBlue
                                : _getStatusColor(pair.status),
                          ),
                        ),
                      ),
                    ],
                  ),
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
        return CupertinoColors.systemYellow;
    }
  }
}

class _RealAssetPool extends StatefulWidget {
  final String type;
  final List<ProjectAsset> pool;
  final Function(ProjectAsset) onDelete;

  const _RealAssetPool({
    required this.type,
    required this.pool,
    required this.onDelete,
  });

  @override
  State<_RealAssetPool> createState() => _RealAssetPoolState();
}

class _RealAssetPoolState extends State<_RealAssetPool> {
  ProjectAsset? _selectedAsset;

  @override
  Widget build(BuildContext context) {
    if (widget.pool.isEmpty) {
      return Center(child: Text("No ${widget.type} assets imported."));
    }

    final theme = MacosTheme.of(context);

    return ListView.builder(
      itemCount: widget.pool.length,
      itemExtent: 64.0, // Slightly taller to comfortably fit the file path
      itemBuilder: (context, i) {
        final asset = widget.pool[i];
        final isSelected = _selectedAsset == asset;

        final macBlue = CupertinoColors.systemBlue.resolveFrom(context);
        final bgColor = isSelected
            ? macBlue.withValues(alpha: 0.15)
            : CupertinoColors.transparent;
        final textColor = theme.typography.body.color;
        final iconColor = isSelected ? macBlue : CupertinoColors.systemGrey;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _selectedAsset = asset),
          child: Container(
            height: 64.0,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: bgColor,
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: Row(
              children: [
                MacosIcon(
                  widget.type == "Audio"
                      ? CupertinoIcons.waveform
                      : (widget.type == "Text"
                            ? CupertinoIcons.doc_text
                            : CupertinoIcons.book),
                  color: iconColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        asset.filename,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        asset.path,
                        style: theme.typography.footnote.copyWith(
                          color: CupertinoColors.systemGrey,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                MacosIconButton(
                  icon: const MacosIcon(
                    CupertinoIcons.trash,
                    color: CupertinoColors.destructiveRed,
                  ),
                  onPressed: () {
                    if (_selectedAsset == asset) {
                      setState(() => _selectedAsset = null);
                    }
                    widget.onDelete(asset);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RealAlignmentList extends StatelessWidget {
  final List<AlignmentPair> pairs;
  final AlignmentPair? selectedPair;
  final Function(AlignmentPair) onSelect;
  final Function(AlignmentPair) onOpenPair;
  final Function(AlignmentPair) onDelete;

  const _RealAlignmentList({
    required this.pairs,
    required this.selectedPair,
    required this.onSelect,
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

    final theme = MacosTheme.of(context);

    // Changed from ListView.separated to ListView.builder to remove gaps
    return ListView.builder(
      itemCount: pairs.length,
      itemExtent: 56.0, // Fixed height to match the fragment list
      itemBuilder: (context, i) {
        final pair = pairs[i];
        final bool isReady =
            pair.audioAssetId != null && pair.textAssetId != null;
        final bool isSelected = selectedPair == pair;

        final macBlue = CupertinoColors.systemBlue.resolveFrom(context);
        final bgColor = isSelected
            ? macBlue.withValues(alpha: 0.15)
            : CupertinoColors.transparent;
        final textColor = theme.typography.body.color;
        final iconColor = isSelected ? macBlue : CupertinoColors.systemGrey;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onSelect(pair),
          onDoubleTap: () {
            if (isReady) onOpenPair(pair);
          },
          child: Container(
            height: 56.0,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: bgColor,
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: Row(
              children: [
                MacosIcon(CupertinoIcons.link, color: iconColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pair.id,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      if (!isReady)
                        Text(
                          "Missing Audio or Text. Select in Inspector.",
                          style: theme.typography.footnote.copyWith(
                            color: CupertinoColors.destructiveRed,
                          ),
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
                    // Match pill background to selection state
                    color: isSelected
                        ? macBlue.withValues(alpha: 0.15)
                        : (pair.status == AlignmentStatus.reviewed
                              ? CupertinoColors.activeGreen.withValues(
                                  alpha: 0.2,
                                )
                              : CupertinoColors.systemYellow.withValues(
                                  alpha: 0.2,
                                )),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    pair.status.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      // Match pill text to selection state
                      color: isSelected
                          ? macBlue
                          : (pair.status == AlignmentStatus.reviewed
                                ? CupertinoColors.activeGreen
                                : CupertinoColors.systemYellow),
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
