import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:path/path.dart' as p;

class ProjectSettingsDialog extends StatefulWidget {
  final Project project;

  const ProjectSettingsDialog({super.key, required this.project});

  @override
  State<ProjectSettingsDialog> createState() => _ProjectSettingsDialogState();
}

class _ProjectSettingsDialogState extends State<ProjectSettingsDialog> {
  late TextEditingController _nameCtrl;
  late TextEditingController _prefixCtrl;
  String? _dictPath;
  int _idMode = 0;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.project.name);
    _prefixCtrl = TextEditingController(
      text: widget.project.generatedIdPrefix ?? "",
    );
    _dictPath = widget.project.dictionaryPath;

    if (widget.project.hasIds) {
      _idMode = 1;
    } else if (widget.project.generateIds) {
      _idMode = 2;
    } else {
      _idMode = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Project Settings"),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: "Project Name"),
              ),
              const SizedBox(height: 24),

              const Text(
                "Dictionary (JSON)",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _dictPath != null
                          ? p.basename(_dictPath!)
                          : "None Selected",
                      style: TextStyle(
                        color: _dictPath != null ? Colors.teal : Colors.grey,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['json'],
                      );
                      if (result != null) {
                        setState(() => _dictPath = result.files.single.path);
                      }
                    },
                    child: const Text("Browse"),
                  ),
                  if (_dictPath != null)
                    IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () => setState(() => _dictPath = null),
                    ),
                ],
              ),
              const SizedBox(height: 24),

              const Text(
                "Verse ID Strategy",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    RadioListTile<int>(
                      title: const Text("None"),
                      value: 0,
                      groupValue: _idMode,
                      onChanged: (v) => setState(() => _idMode = v!),
                    ),
                    RadioListTile<int>(
                      title: const Text("IDs are in the text files"),
                      value: 1,
                      groupValue: _idMode,
                      onChanged: (v) => setState(() => _idMode = v!),
                    ),
                    RadioListTile<int>(
                      title: const Text("Auto-Generate IDs"),
                      value: 2,
                      groupValue: _idMode,
                      onChanged: (v) => setState(() => _idMode = v!),
                    ),
                    if (_idMode == 2)
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: TextField(
                          controller: _prefixCtrl,
                          decoration: const InputDecoration(
                            labelText: "Fixed Book Prefix (e.g. 40)",
                            border: OutlineInputBorder(),
                            helperText:
                                "Format: {Prefix}{Recording:000}{Verse:000}",
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "Note: Changing the ID strategy will only affect alignments run AFTER saving. To update existing completed files, you must run them again.",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text("Cancel"),
        ),
        FilledButton(
          onPressed: () {
            if (_idMode == 2 && _prefixCtrl.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Please enter a prefix.")),
              );
              return;
            }

            widget.project.name = _nameCtrl.text;
            widget.project.dictionaryPath = _dictPath;
            widget.project.hasIds = (_idMode == 1);
            widget.project.generateIds = (_idMode == 2);
            widget.project.generatedIdPrefix = _idMode == 2
                ? _prefixCtrl.text.trim()
                : null;

            Navigator.of(context).pop(true);
          },
          child: const Text("Save"),
        ),
      ],
    );
  }
}
