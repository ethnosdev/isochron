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
  final _idPrefixCtrl = TextEditingController();

  // 0 = None, 1 = In Text, 2 = Auto-Generate
  int _idMode = 0;
  bool _isAnalyzing = false;

  List<String> _audioFiles = [];
  List<String> _textFiles = [];
  String? _dictPath;

  int _currentStep = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("New Project Setup")),
      body: Stack(
        children: [
          Stepper(
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
                      child: Text(
                        _currentStep == 2 ? "Create Project" : "Next",
                      ),
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
              Step(
                title: const Text("Select Files"),
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _projectNameCtrl,
                      decoration: const InputDecoration(
                        labelText: "Project Name",
                      ),
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
                    const SizedBox(height: 24),

                    // --- ID STRATEGY BLOCK ---
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Verse ID Strategy",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          RadioListTile<int>(
                            title: const Text("None"),
                            subtitle: const Text("Do not use verse IDs"),
                            value: 0,
                            groupValue: _idMode,
                            onChanged: (v) => setState(() => _idMode = v!),
                          ),
                          RadioListTile<int>(
                            title: const Text("IDs are in the text files"),
                            subtitle: const Text(
                              "e.g. '40001001 In the beginning...'",
                            ),
                            value: 1,
                            groupValue: _idMode,
                            onChanged: (v) => setState(() => _idMode = v!),
                          ),
                          RadioListTile<int>(
                            title: const Text("Auto-Generate IDs"),
                            subtitle: const Text(
                              "Based on book prefix + file order + line number",
                            ),
                            value: 2,
                            groupValue: _idMode,
                            onChanged: (v) => setState(() => _idMode = v!),
                          ),
                          if (_idMode == 2)
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 32,
                                right: 32,
                                top: 8,
                              ),
                              child: TextField(
                                controller: _idPrefixCtrl,
                                decoration: const InputDecoration(
                                  labelText: "Fixed Book Prefix (e.g. 40)",
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // -------------------------
                    const SizedBox(height: 24),
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

              Step(
                title: const Text("Verify Pairs"),
                content: SizedBox(
                  height: 400,
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

              Step(
                title: const Text("Finish"),
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                            Expanded(
                              child: Text(
                                "Warning: Counts do not match. Extra files will be ignored.",
                              ),
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

          if (_isAnalyzing)
            Container(
              color: Colors.black45,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      "Analyzing dictionary matches...",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
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

  void _nextStep() async {
    if (_currentStep == 0) {
      if (_audioFiles.isEmpty || _textFiles.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please select audio and text files.")),
        );
        return;
      }

      if (_idMode == 2 && _idPrefixCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please enter a Fixed Book Prefix.")),
        );
        return;
      }

      if (_dictPath != null) {
        setState(() => _isAnalyzing = true);
        try {
          final jsonString = await File(_dictPath!).readAsString();
          final rawMap = jsonDecode(jsonString) as Map<String, dynamic>;
          final rules = rawMap.map((k, v) => MapEntry(k, v.toString()));

          final result = await compute(
            _analyzeAllFiles,
            _AnalysisRequest(_textFiles, rules, _idMode == 1),
          );

          setState(() => _isAnalyzing = false);

          if (!mounted) return;

          final bool confirm =
              await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (_) => TransliterationPreviewDialog(
                  dictName: p.basename(_dictPath!),
                  previewLines: result.previewLines,
                  unknownChars: result.unknownChars,
                ),
              ) ??
              false;

          if (!confirm) return;
        } catch (e) {
          setState(() => _isAnalyzing = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Error checking dictionary: $e")),
            );
          }
          return;
        }
      }

      _audioFiles.sort((a, b) => p.basename(a).compareTo(p.basename(b)));
      _textFiles.sort((a, b) => p.basename(a).compareTo(p.basename(b)));
    }

    if (_currentStep == 2) {
      final service = ProjectService();
      final project = await service.createNewProject(
        _projectNameCtrl.text,
        _audioFiles,
        _textFiles,
        _dictPath,
        _idMode == 1, // hasIds
        _idMode == 2, // generateIds
        _idMode == 2 ? _idPrefixCtrl.text.trim() : null, // generatedIdPrefix
      );

      if (project != null && mounted) {
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
                final result = await FilePicker.platform.pickFiles(
                  type: type,
                  allowMultiple: true,
                  allowedExtensions: extensions,
                  initialDirectory: settings.lastSourceDir,
                );
                if (result != null) {
                  if (result.files.isNotEmpty &&
                      result.files.first.path != null) {
                    await settings.setLastSourceDir(
                      File(result.files.first.path!).parent.path,
                    );
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
            style: const TextStyle(color: Colors.teal),
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
                if (result != null) onSelected(result.files.single.path);
              },
              child: const Text("Browse..."),
            ),
          ],
        ),
        if (current != null)
          Text(p.basename(current), style: const TextStyle(color: Colors.teal)),
      ],
    );
  }
}

// Keeping your _PairingList widget here from before
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
    final int count = audioFiles.length > textFiles.length
        ? audioFiles.length
        : textFiles.length;
    return Row(
      children: [
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
        Container(width: 1, color: Colors.grey),
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
                      key: ValueKey(textFiles[i]),
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
  final nonLatinRegex = RegExp(r'[^\x00-\x7F]');

  for (int i = 0; i < req.filePaths.length; i++) {
    final file = File(req.filePaths[i]);
    if (!file.existsSync()) continue;

    final lines = await file.readAsLines();
    for (var line in lines) {
      if (line.trim().isEmpty) continue;
      String textToProcess = line;
      if (req.hasIds) {
        final parts = line.trim().split(' ');
        if (parts.length > 1) textToProcess = parts.sublist(1).join(' ');
      }
      final converted = Transliterator.convert(textToProcess, req.rules);
      final matches = nonLatinRegex.allMatches(converted);
      for (var m in matches) unknownSet.add(m.group(0)!);
      if (i == 0 && previewLines.length < 5) previewLines.add(converted);
    }
  }
  return _AnalysisResult(previewLines, unknownSet.toList()..sort());
}
