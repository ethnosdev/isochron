import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:isochron_cli/isochron_cli.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'package:isochron_flutter/ui/dialogs/transliteration_preview_dialog.dart';
import 'package:isochron_flutter/ui/project/project_dashboard.dart';
import 'package:path/path.dart' as p;
import '../../services/project_service.dart';

class ProjectCreationWizard extends StatefulWidget {
  const ProjectCreationWizard({super.key});

  @override
  State<ProjectCreationWizard> createState() => _ProjectCreationWizardState();
}

class _ProjectCreationWizardState extends State<ProjectCreationWizard> {
  final _projectNameCtrl = TextEditingController(text: "My New Project");
  bool _hasIds = false;
  bool _isAnalyzing = false;

  List<String> _audioFiles = [];
  List<String> _textFiles = [];
  String? _dictPath;

  int _currentStep = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("New Project Setup")),
      body: Stepper(
        type: StepperType.horizontal,
        currentStep: _currentStep,
        onStepContinue: _nextStep,
        onStepCancel: _prevStep,
        controlsBuilder: (context, details) {
          return Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Row(
              children: [
                FilledButton(
                  onPressed: details.onStepContinue,
                  child: Text(_currentStep == 2 ? "Create Project" : "Next"),
                ),
                const SizedBox(width: 12),
                if (_currentStep > 0)
                  TextButton(
                    onPressed: details.onStepCancel,
                    child: const Text("Back"),
                  ),
              ],
            ),
          );
        },
        steps: [
          // STEP 1: INPUTS
          Step(
            title: const Text("Select Files"),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _projectNameCtrl,
                  decoration: const InputDecoration(labelText: "Project Name"),
                ),
                const SizedBox(height: 20),
                _buildFileSelector(
                  "Audio Files",
                  _audioFiles,
                  FileType.audio,
                  (files) => setState(() => _audioFiles = files),
                ),
                const SizedBox(height: 20),
                _buildFileSelector(
                  "Transcripts (Text)",
                  _textFiles,
                  FileType.custom,
                  (files) => setState(() => _textFiles = files),
                  extensions: ['txt'],
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Text files start with ID?"),
                  subtitle: const Text("e.g. '4001001 In the beginning...'"),
                  value: _hasIds,
                  onChanged: (val) => setState(() => _hasIds = val ?? false),
                ),
                const SizedBox(height: 20),
                const Text("Optional:"),
                _buildSingleFileSelector(
                  "Transliteration Dictionary (JSON)",
                  _dictPath,
                  (path) => setState(() => _dictPath = path),
                ),
              ],
            ),
            isActive: _currentStep >= 0,
          ),

          // STEP 2: PAIRING
          Step(
            title: const Text("Verify Pairs"),
            content: SizedBox(
              height: 400, // Fixed height for list
              child: _PairingList(
                audioFiles: _audioFiles,
                textFiles: _textFiles,
                onReorderText: (oldIdx, newIdx) {
                  setState(() {
                    if (newIdx > oldIdx) newIdx -= 1;
                    final item = _textFiles.removeAt(oldIdx);
                    _textFiles.insert(newIdx, item);
                  });
                },
              ),
            ),
            isActive: _currentStep >= 1,
          ),

          // STEP 3: CONFIRM
          Step(
            title: const Text("Finish"),
            content: Column(
              children: [
                Text("Ready to create '${_projectNameCtrl.text}'"),
                Text("Audio Files: ${_audioFiles.length}"),
                Text("Text Files: ${_textFiles.length}"),
                if (_audioFiles.length != _textFiles.length)
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(8),
                    color: Colors.orange.shade100,
                    child: Row(
                      children: const [
                        Icon(Icons.warning, color: Colors.orange),
                        SizedBox(width: 8),
                        Text(
                          "Warning: Counts do not match. Some files may be ignored.",
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            isActive: _currentStep >= 2,
          ),
        ],
      ),
    );
  }

  void _nextStep() async {
    if (_currentStep == 0) {
      if (_audioFiles.isEmpty || _textFiles.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please select audio and text files.")),
        );
        return;
      }

      if (_dictPath != null) {
        setState(() => _isAnalyzing = true);

        try {
          // 1. Load Dictionary
          final jsonString = await File(_dictPath!).readAsString();
          final Map<String, dynamic> rawMap = jsonDecode(jsonString);
          final rules = rawMap.map((k, v) => MapEntry(k, v.toString()));

          // 2. Run Analysis on ALL files via Compute
          final result = await compute(
            _analyzeAllFiles,
            _AnalysisRequest(_textFiles, rules, _hasIds),
          );

          setState(() => _isAnalyzing = false);

          if (!mounted) return;

          // 3. Show Result
          final bool confirm =
              await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (_) => TransliterationPreviewDialog(
                  dictName: p.basename(_dictPath!),
                  previewLines:
                      result.previewLines, // Show samples from first file
                  unknownChars: result.unknownChars, // Collected from ALL files
                ),
              ) ??
              false;

          if (!confirm) return; // Stop if user cancels
        } catch (e) {
          setState(() => _isAnalyzing = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Error checking dictionary: $e")),
            );
          }
          return; // Stop on error
        }
      }

      // Sort initially for better UX before manual reordering
      _audioFiles.sort((a, b) => p.basename(a).compareTo(p.basename(b)));
      _textFiles.sort((a, b) => p.basename(a).compareTo(p.basename(b)));
    }

    if (_currentStep == 2) {
      // CREATE PROJECT
      final service = ProjectService();
      final project = await service.createNewProject(
        _projectNameCtrl.text,
        _audioFiles,
        _textFiles,
        _dictPath,
        _hasIds,
      );

      if (project != null && mounted) {
        // NAVIGATE TO DASHBOARD (Will implement next)
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => ProjectDashboard(project: project)),
        );
      }
      return;
    }

    setState(() => _currentStep++);
  }

  void _prevStep() {
    if (_currentStep > 0) setState(() => _currentStep--);
  }

  Widget _buildFileSelector(
    String title,
    List<String> current,
    FileType type,
    Function(List<String>) onSelected, {
    List<String>? extensions,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            OutlinedButton(
              onPressed: () async {
                final settings = UserSettingsService();
                final lastDir = settings.lastSourceDir;
                final result = await FilePicker.platform.pickFiles(
                  type: type,
                  allowMultiple: true,
                  allowedExtensions: extensions,
                  initialDirectory: lastDir,
                );
                if (result != null) {
                  if (result.files.isNotEmpty &&
                      result.files.first.path != null) {
                    final parent = File(result.files.first.path!).parent.path;
                    await settings.setLastSourceDir(parent);
                  }
                  onSelected(result.paths.whereType<String>().toList());
                }
              },
              child: const Text("Browse..."),
            ),
          ],
        ),
        if (current.isNotEmpty)
          Text(
            "${current.length} files selected",
            style: TextStyle(color: Colors.teal),
          ),
      ],
    );
  }

  Widget _buildSingleFileSelector(
    String title,
    String? current,
    Function(String?) onSelected,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            OutlinedButton(
              onPressed: () async {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['json'],
                );
                if (result != null) {
                  onSelected(result.files.single.path);
                }
              },
              child: const Text("Browse..."),
            ),
          ],
        ),
        if (current != null)
          Text(p.basename(current), style: TextStyle(color: Colors.teal)),
      ],
    );
  }
}

class _PairingList extends StatelessWidget {
  final List<String> audioFiles;
  final List<String> textFiles;
  final Function(int, int) onReorderText;

  const _PairingList({
    required this.audioFiles,
    required this.textFiles,
    required this.onReorderText,
  });

  @override
  Widget build(BuildContext context) {
    // We visualize based on the longer list to show gaps
    final int count = audioFiles.length > textFiles.length
        ? audioFiles.length
        : textFiles.length;

    return Row(
      children: [
        // Left Column: Audio (Fixed)
        Expanded(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text(
                  "Audio (Fixed Order)",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: count,
                  itemExtent: 50,
                  itemBuilder: (context, i) {
                    final name = i < audioFiles.length
                        ? p.basename(audioFiles[i])
                        : "-";
                    return Container(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.grey.shade200),
                        ),
                      ),
                      child: Text(name, style: const TextStyle(fontSize: 12)),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // Divider
        Container(width: 1, color: Colors.grey),

        // Right Column: Text (Reorderable)
        Expanded(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text(
                  "Text (Drag to Align)",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  itemCount: textFiles.length,
                  itemExtent: 50,
                  onReorder: onReorderText,
                  itemBuilder: (context, i) {
                    return Container(
                      key: ValueKey(
                        textFiles[i],
                      ), // Key must be unique based on path
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(
                          bottom: BorderSide(color: Colors.grey.shade200),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.drag_handle,
                            size: 16,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              p.basename(textFiles[i]),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// --- BACKGROUND ISOLATE LOGIC ---

class _AnalysisRequest {
  final List<String> filePaths;
  final Map<String, String> rules;
  final bool hasIds;
  _AnalysisRequest(this.filePaths, this.rules, this.hasIds);
}

class _AnalysisResult {
  final List<String> previewLines;
  final List<String> unknownChars;
  _AnalysisResult(this.previewLines, this.unknownChars);
}

Future<_AnalysisResult> _analyzeAllFiles(_AnalysisRequest req) async {
  final Set<String> unknownSet = {};
  final List<String> previewLines = [];
  final nonLatinRegex = RegExp(r'[^\x00-\x7F]'); // Detects non-ASCII

  // Loop through ALL files
  for (int i = 0; i < req.filePaths.length; i++) {
    final file = File(req.filePaths[i]);
    if (!file.existsSync()) continue;

    final lines = await file.readAsLines();

    for (var line in lines) {
      if (line.trim().isEmpty) continue;

      String textToProcess = line;

      // Strip IDs
      if (req.hasIds) {
        final parts = line.trim().split(' ');
        if (parts.length > 1) {
          textToProcess = parts.sublist(1).join(' ');
        }
      }

      // Transliterate
      final converted = Transliterator.convert(textToProcess, req.rules);

      // Collect Unknowns
      final matches = nonLatinRegex.allMatches(converted);
      for (var m in matches) {
        unknownSet.add(m.group(0)!);
      }

      // Save Preview (Only from the first file, first 5 lines)
      if (i == 0 && previewLines.length < 5) {
        previewLines.add(converted);
      }
    }
  }

  final sortedUnknowns = unknownSet.toList()..sort();
  return _AnalysisResult(previewLines, sortedUnknowns);
}
