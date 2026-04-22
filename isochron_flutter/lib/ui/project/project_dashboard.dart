import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:isochron_cli/isochron_cli.dart';
import 'package:isochron_flutter/ui/dialogs/global_settings_dialog.dart';
import 'package:isochron_flutter/ui/dialogs/project_settings_dialog.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:isochron_flutter/ui/widgets/theme_toggle_button.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/alignment_service.dart';
import '../home_screen.dart'; // The Editor

class ProjectDashboard extends StatefulWidget {
  final Project project;

  const ProjectDashboard({super.key, required this.project});

  @override
  State<ProjectDashboard> createState() => _ProjectDashboardState();
}

class _ProjectDashboardState extends State<ProjectDashboard> {
  late Project _project;
  final AlignmentService _alignmentService = AlignmentService();

  // Track active batch processing
  bool _isBatchRunning = false;
  String _batchStatus = "";
  double _currentProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _project = widget.project;
  }

  /// Saves the project metadata (status updates) to disk
  Future<void> _saveProjectState() async {
    await _project.save();
    setState(() {}); // Refresh UI
  }

  @override
  Widget build(BuildContext context) {
    // 1. Grab the dynamic color scheme for the current theme
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_project.name, style: const TextStyle(fontSize: 16)),
            Text(
              "${_project.items.length} files",
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ), // <-- Dynamic color
            ),
          ],
        ),
        actions: [
          const ThemeToggleButton(), // Assuming you added this earlier!
          if (_isBatchRunning)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(_batchStatus, style: const TextStyle(fontSize: 12)),
              ),
            ),
          if (!_isBatchRunning) ...[
            TextButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text("Run All Pending"),
              onPressed: _runBatch,
            ),
          ],
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'export_all_csv') {
                _exportBatchCsv();
              } else if (v == 'project_settings') {
                final result = await showDialog<ProjectSettingsResult>(
                  context: context,
                  builder: (_) => ProjectSettingsDialog(project: _project),
                );
                if (result != null && result.settingsChanged) {
                  await _saveProjectState();
                  if (result.applyRetroactively) {
                    await _applyIdStrategyToSavedFiles();
                  }
                }
              } else if (v == 'app_settings') {
                await showDialog(
                  context: context,
                  builder: (_) => const GlobalSettingsDialog(),
                );
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'project_settings',
                child: Row(
                  children: [
                    Icon(
                      Icons.folder_special,
                      color: colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text("Project Settings"),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'app_settings',
                child: Row(
                  children: [
                    Icon(
                      Icons.settings,
                      color: colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text("App Settings (Paths)"),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'export_all_csv',
                child: Row(
                  children: [
                    Icon(
                      Icons.download,
                      color: colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text("Export All to Single CSV"),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isBatchRunning) LinearProgressIndicator(value: _currentProgress),

          Expanded(
            child: ListView.separated(
              itemCount: _project.items.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: Theme.of(context).dividerColor),
              itemBuilder: (ctx, i) {
                final item = _project.items[i];

                final isCompleted =
                    item.status == ProjectItemStatus.done ||
                    item.status == ProjectItemStatus.reviewed;

                return ListTile(
                  // 1. ADD THIS: Makes the whole row clickable to open the editor
                  onTap: () => _openEditor(item),

                  // 2. ADD THIS: Explicitly sets a beautiful, theme-aware hover color
                  // (0.04 opacity is the Material Design standard for hover states)
                  hoverColor: colorScheme.onSurface.withValues(alpha: 0.04),

                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),

                  leading: _buildStatusIcon(item.status, colorScheme),
                  title: Text(p.basename(item.audioPath)),
                  subtitle: Text(
                    "JSON: ${item.outputFilename}",
                    style: TextStyle(
                      color: isCompleted
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!_isBatchRunning)
                        IconButton(
                          icon: const Icon(Icons.bolt, size: 20),
                          tooltip: "Align this file",
                          color: colorScheme.onSurfaceVariant,
                          onPressed: () => _runSingleItem(i),
                        ),
                      IconButton(
                        icon: const Icon(Icons.edit),
                        tooltip: "Open Editor",
                        color: colorScheme.primary,
                        onPressed: () => _openEditor(item),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon(ProjectItemStatus status, ColorScheme colorScheme) {
    switch (status) {
      case ProjectItemStatus.pending:
        return Icon(Icons.circle_outlined, color: colorScheme.outline);
      case ProjectItemStatus.processing:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case ProjectItemStatus.done:
        return Icon(Icons.auto_awesome, color: colorScheme.secondary);
      case ProjectItemStatus.reviewed:
        return Icon(Icons.check_circle, color: colorScheme.primary);
      case ProjectItemStatus.error:
        return Icon(Icons.error, color: colorScheme.error);
    }
  }

  // --- ACTIONS ---

  Future<void> _openEditor(ProjectItem item) async {
    final index = _project.items.indexOf(item);

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MainScreen(
          project: _project, // Passed the whole project
          initialItemIndex: index, // Passed the starting index
          onNotifySaved: (savedIndex) async {
            // Update the status of whichever file was just saved
            setState(() {
              _project.items[savedIndex] = _project.items[savedIndex].copyWith(
                status: ProjectItemStatus.reviewed,
              );
            });
            // Persist the status change to project.json
            await _project.save();
          },
        ),
      ),
    );

    // Refresh UI when returning to Dashboard
    setState(() {});
  }

  Future<void> _runBatch() async {
    setState(() => _isBatchRunning = true);

    final prefs = await SharedPreferences.getInstance();
    final ffmpeg = prefs.getString('ffmpeg') ?? 'ffmpeg';
    final espeak = prefs.getString('espeak') ?? 'espeak-ng';

    // Filter for pending items
    final pendingIndices = _project.items
        .asMap()
        .entries
        .where((e) => e.value.status == ProjectItemStatus.pending)
        .map((e) => e.key)
        .toList();

    for (int idx in pendingIndices) {
      if (!mounted) break;
      await _processItem(idx, ffmpeg, espeak);
    }

    if (mounted) {
      setState(() {
        _isBatchRunning = false;
        _batchStatus = "Batch Complete";
        _currentProgress = 0.0;
      });
    }
  }

  Future<void> _runSingleItem(int index) async {
    setState(() => _isBatchRunning = true);
    final prefs = await SharedPreferences.getInstance();
    final ffmpeg = prefs.getString('ffmpeg') ?? 'ffmpeg';
    final espeak = prefs.getString('espeak') ?? 'espeak-ng'; // Fixed typo

    await _processItem(index, ffmpeg, espeak);

    if (mounted) setState(() => _isBatchRunning = false);
  }

  Future<void> _processItem(int index, String ffmpeg, String espeak) async {
    final item = _project.items[index];

    setState(() {
      _project.items[index] = item.copyWith(
        status: ProjectItemStatus.processing,
      );
      _batchStatus = "Processing ${p.basename(item.audioPath)}...";
    });

    try {
      // Pass the new ID generation parameters. Recording number is index + 1
      final fragments = await _alignmentService.runIsochron(
        textPath: item.textPath,
        audioPath: item.audioPath,
        ffmpegPath: ffmpeg,
        espeakPath: espeak,
        dictPath: _project.dictionaryPath,
        hasIds: _project.hasIds,
        generateIds: _project.generateIds,
        generatedIdPrefix: _project.generatedIdPrefix,
        recordingNumber:
            index + 1, // <--- Passes the recording number based on list order
        onProgress: (status, prog) {
          if (mounted) setState(() => _currentProgress = prog);
        },
      );

      final absPath = item.getAbsoluteOutputPath(_project.directoryPath);

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

      final jsonString = const JsonEncoder.withIndent('  ').convert(jsonList);
      await File(absPath).writeAsString(jsonString);

      setState(() {
        _project.items[index] = item.copyWith(status: ProjectItemStatus.done);
      });
    } catch (e) {
      debugPrint("Error processing ${item.id}: $e");
      setState(() {
        _project.items[index] = item.copyWith(status: ProjectItemStatus.error);
      });
    } finally {
      await _saveProjectState();
    }
  }

  Future<void> _exportBatchCsv() async {
    // 1. Filter for DONE and REVIEWED items
    final exportableItems = _project.items
        .where(
          (i) =>
              i.status == ProjectItemStatus.done ||
              i.status == ProjectItemStatus.reviewed,
        )
        .toList();

    if (exportableItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No completed items to export.")),
      );
      return;
    }

    // 2. Ask for Save Location
    final String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Combined CSV',
      fileName: '${_project.name.replaceAll(" ", "_")}_full.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (outputFile == null) return;

    setState(() => _isBatchRunning = true);
    _batchStatus = "Generating CSV...";

    try {
      final masterBuffer = StringBuffer();
      // Write Header Once
      masterBuffer.writeln('id,verse_id,recording_id,start,end');

      for (var item in exportableItems) {
        final absJsonPath = item.getAbsoluteOutputPath(_project.directoryPath);
        final file = File(absJsonPath);

        if (await file.exists()) {
          // A. Parse JSON
          final content = await file.readAsString();
          final List<dynamic> jsonList = jsonDecode(content);

          final fragments = jsonList
              .map(
                (j) =>
                    Fragment(index: j['index'], id: j['id'], text: j['text'])
                      ..setRealTiming(
                        start: (j['start'] as num).toDouble(),
                        end: (j['end'] as num).toDouble(),
                      ),
              )
              .toList();

          /// Could ask user for this
          final recId = 'xxx';

          // C. Append Lines (Skip header logic in helper, do manually here for speed)
          for (final f in fragments) {
            masterBuffer.write('${f.index},');
            masterBuffer.write('${f.id ?? ""},');
            masterBuffer.write('$recId,'); // Automatic ID
            masterBuffer.write('${f.realStart.toStringAsFixed(3)},');
            masterBuffer.write(f.realEnd.toStringAsFixed(3));
            masterBuffer.writeln();
          }
        }
      }

      // 3. Write File
      await File(outputFile).writeAsString(masterBuffer.toString());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Exported ${exportableItems.length} files to CSV"),
          ),
        );
      }
    } catch (e) {
      debugPrint("CSV Export Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBatchRunning = false;
          _batchStatus = "";
        });
      }
    }
  }

  Future<void> _applyIdStrategyToSavedFiles() async {
    setState(() => _isBatchRunning = true);
    _batchStatus = "Updating IDs in saved files...";

    int updatedCount = 0;

    // Loop through all project items
    for (int index = 0; index < _project.items.length; index++) {
      final item = _project.items[index];
      final absPath = item.getAbsoluteOutputPath(_project.directoryPath);
      final file = File(absPath);

      // Only touch files that already exist (already aligned)
      if (await file.exists()) {
        try {
          final content = await file.readAsString();
          final List<dynamic> jsonList = jsonDecode(content);
          bool modified = false;

          for (int j = 0; j < jsonList.length; j++) {
            final Map<String, dynamic> frag = jsonList[j];

            // Strategy: Auto-Generate
            if (_project.generateIds && _project.generatedIdPrefix != null) {
              final recStr = (index + 1).toString().padLeft(
                3,
                '0',
              ); // file index + 1
              final verseStr = (j + 1).toString().padLeft(
                3,
                '0',
              ); // verse index + 1
              final newId = '${_project.generatedIdPrefix}$recStr$verseStr';

              if (frag['id'] != newId) {
                frag['id'] = newId;
                modified = true;
              }
            }
            // Strategy: IDs are in Text
            else if (_project.hasIds) {
              final textLines = await File(item.textPath).readAsLines();
              final cleanLines = textLines
                  .where((l) => l.trim().isNotEmpty)
                  .toList();

              if (j < cleanLines.length) {
                final parts = cleanLines[j].trim().split(' ');
                if (parts.length > 1) {
                  final extractedId = parts.first;
                  if (frag['id'] != extractedId) {
                    frag['id'] = extractedId;
                    modified = true;
                  }
                }
              }
            }
          }

          // Save the JSON back to disk ONLY if it actually changed
          if (modified) {
            final jsonString = const JsonEncoder.withIndent(
              '  ',
            ).convert(jsonList);
            await file.writeAsString(jsonString);
            updatedCount++;
          }
        } catch (e) {
          debugPrint("Error updating IDs for ${item.audioPath}: $e");
        }
      }
    }

    if (mounted) {
      setState(() {
        _isBatchRunning = false;
        _batchStatus = "";
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Successfully updated IDs in $updatedCount files."),
        ),
      );
    }
  }
}
