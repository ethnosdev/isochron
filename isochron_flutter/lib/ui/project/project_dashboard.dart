import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:isochron_cli/isochron_cli.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
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
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_project.name, style: const TextStyle(fontSize: 16)),
            Text(
              "${_project.items.length} files",
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
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
            onSelected: (v) {
              if (v == 'export_all_csv') _exportBatchCsv();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'export_all_csv',
                child: Text("Export All to Single CSV"),
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
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final item = _project.items[i];
                return ListTile(
                  leading: _buildStatusIcon(item.status),
                  title: Text(p.basename(item.audioPath)),
                  subtitle: Text(
                    "JSON: ${item.outputFilename}",
                    style: TextStyle(
                      color: item.status == ProjectItemStatus.done
                          ? Colors.green
                          : Colors.grey,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // "Run Individual" Button
                      if (!_isBatchRunning)
                        IconButton(
                          icon: const Icon(Icons.bolt, size: 20),
                          tooltip: "Align this file",
                          onPressed: () => _runSingleItem(i),
                        ),
                      // "Edit" Button
                      IconButton(
                        icon: const Icon(Icons.edit),
                        tooltip: "Open Editor",
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

  Widget _buildStatusIcon(ProjectItemStatus status) {
    switch (status) {
      case ProjectItemStatus.pending:
        return const Icon(Icons.circle_outlined, color: Colors.grey);
      case ProjectItemStatus.processing:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case ProjectItemStatus.done:
        return const Icon(Icons.check_circle, color: Colors.green);
      case ProjectItemStatus.error:
        return const Icon(Icons.error, color: Colors.red);
    }
  }

  // --- ACTIONS ---

  Future<void> _openEditor(ProjectItem item) async {
    // Navigate to MainScreen.
    // Note: We need a way to tell MainScreen to load THIS item.
    // We can do this by passing arguments or calling a method after push.
    // A clean way is to make MainScreen take an optional 'ProjectItem' + 'ProjectRoot'

    // For now, let's assume we modify MainScreen to accept these:
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _EditorWrapper(item: item, project: _project),
      ),
    );

    // When we return, the status might have changed (if user saved), so refresh
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

    // Update UI to Processing
    setState(() {
      _project.items[index] = item.copyWith(
        status: ProjectItemStatus.processing,
      );
      _batchStatus = "Processing ${p.basename(item.audioPath)}...";
    });

    try {
      // 1. Run Alignment
      final fragments = await _alignmentService.runIsochron(
        textPath: item.textPath,
        audioPath: item.audioPath,
        ffmpegPath: ffmpeg,
        espeakPath: espeak,
        dictPath: _project.dictionaryPath,
        onProgress: (status, prog) {
          if (mounted) setState(() => _currentProgress = prog);
        },
      );

      // 2. Save JSON Output
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

      // 3. Mark Done
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
    // 1. Filter for DONE items
    final doneItems = _project.items
        .where((i) => i.status == ProjectItemStatus.done)
        .toList();

    if (doneItems.isEmpty) {
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

      for (var item in doneItems) {
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

          // B. Determine Recording ID (Use filename without extension)
          // e.g. /path/to/MAT_01.mp3 -> MAT_01
          final recId = p.basenameWithoutExtension(item.audioPath);

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
          SnackBar(content: Text("Exported ${doneItems.length} files to CSV")),
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
}

/// A small wrapper to initialize the MainScreen with project data
class _EditorWrapper extends StatefulWidget {
  final ProjectItem item;
  final Project project;

  const _EditorWrapper({required this.item, required this.project});

  @override
  State<_EditorWrapper> createState() => _EditorWrapperState();
}

class _EditorWrapperState extends State<_EditorWrapper> {
  // We grab the state of MainScreen via GlobalKey or just let MainScreen
  // expose a setup method. But MainScreen manages its own HomeManager.
  // The cleanest way without rewriting MainScreen completely is to
  // wrap it and use the `HomeManager` to load data in `initState`.

  // NOTE: This assumes MainScreen is accessible.
  // Actually, MainScreen instantiates its own HomeManager internally.
  // To fix this dependency injection, we'll modify MainScreen to accept an optional Manager
  // OR we use a GlobalKey to access the state.
  // Let's use the standard Flutter approach: passing arguments to MainScreen.

  @override
  Widget build(BuildContext context) {
    // For this to work, you must update MainScreen constructor
    // to accept 'initialProjectItem' and 'initialProjectRoot'.
    return MainScreen(
      initialProjectItem: widget.item,
      initialProjectRoot: widget.project.directoryPath,
    );
  }
}
