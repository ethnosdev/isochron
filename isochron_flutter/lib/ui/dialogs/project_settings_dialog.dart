import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:path/path.dart' as p;

class ProjectSettingsResult {
  final bool settingsChanged;
  final bool applyRetroactively;
  ProjectSettingsResult(this.settingsChanged, this.applyRetroactively);
}

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
  late String _snapMode;
  late TextEditingController _snapOffsetCtrl;

  // Track original settings to see if they changed
  late int _originalIdMode;
  late String _originalPrefix;
  late String _originalSnapMode;
  int? _originalSnapOffset;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.project.name);
    _prefixCtrl = TextEditingController(
      text: widget.project.generatedIdPrefix ?? "",
    );
    _dictPath = widget.project.dictionaryPath;
    _snapMode = widget.project.snapMode;
    _snapOffsetCtrl = TextEditingController(
      text: widget.project.snapOffset != null
          ? '${widget.project.snapOffset}'
          : '',
    );
    _originalSnapOffset = widget.project.snapOffset;

    if (widget.project.hasIds) {
      _idMode = 1;
    } else if (widget.project.generateIds) {
      _idMode = 2;
    } else {
      _idMode = 0;
    }

    _originalIdMode = _idMode;
    _originalPrefix = _prefixCtrl.text.trim();
    _originalSnapMode = _snapMode;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _prefixCtrl.dispose();
    _snapOffsetCtrl.dispose();
    super.dispose();
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
                      final settings = UserSettingsService();
                      final result = await FilePicker.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['json'],
                        initialDirectory: settings.lastDictDir,
                      );

                      if (result != null && result.files.single.path != null) {
                        final path = result.files.single.path!;
                        // Save the parent folder so it opens here next time
                        await settings.setLastDictDir(File(path).parent.path);
                        setState(() => _dictPath = path);
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
              const SizedBox(height: 24),
              const Text(
                "Snap Mode",
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
                    RadioListTile<String>(
                      title: const Text("Gap (silence in-between phrases)"),
                      value: 'gap',
                      groupValue: _snapMode,
                      onChanged: (v) => setState(() => _snapMode = v!),
                    ),
                    RadioListTile<String>(
                      title: const Text("Onset (where phrase starts)"),
                      value: 'onset',
                      groupValue: _snapMode,
                      onChanged: (v) => setState(() => _snapMode = v!),
                    ),
                    if (_snapMode == 'onset')
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: TextField(
                          controller: _snapOffsetCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Snap offset',
                            hintText: 'e.g 250',
                            suffixText: 'ms',
                            border: OutlineInputBorder(),
                            helperText:
                                'Lead-in before detected onset (ms). Leave blank for none.',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text("Cancel"),
        ),
        FilledButton(
          onPressed: () async {
            if (_idMode == 2 && _prefixCtrl.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Please enter a prefix.")),
              );
              return;
            }

            int? newSnapOffset;
            final snapTrim = _snapOffsetCtrl.text.trim();
            if (_snapMode == 'onset') {
              if (snapTrim.isEmpty) {
                newSnapOffset = null;
              } else {
                final parsed = int.tryParse(snapTrim);
                if (parsed == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Snap offset must be a whole number of ms.',
                      ),
                    ),
                  );
                  return;
                }
                if (parsed < 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Snap offset cannot be negative.'),
                    ),
                  );
                  return;
                }
                newSnapOffset = parsed;
              }
            } else {
              newSnapOffset = widget.project.snapOffset;
            }

            bool applyRetroactively = false;
            final bool idStrategyChanged =
                (_idMode != _originalIdMode) ||
                (_prefixCtrl.text.trim() != _originalPrefix);
            final bool snapOffsetChanged = newSnapOffset != _originalSnapOffset;
            final bool settingsChanged =
                idStrategyChanged ||
                (_snapMode != _originalSnapMode) ||
                snapOffsetChanged;

            // If they changed the ID Strategy to something new, ask them if they want to apply it
            if (idStrategyChanged && _idMode != 0) {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text("Update Existing Files?"),
                  content: const Text(
                    "You changed the Verse ID Strategy.\n\n"
                    "Would you like to automatically inject these new IDs into your existing aligned JSON files now?\n\n"
                    "Note: Your manual timing edits (start/end times) will NOT be overwritten.",
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text("No"),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text("Yes, Update IDs"),
                    ),
                  ],
                ),
              );
              applyRetroactively = confirm ?? false;
            }

            // Apply to project object
            widget.project.name = _nameCtrl.text;
            widget.project.dictionaryPath = _dictPath;
            widget.project.hasIds = (_idMode == 1);
            widget.project.generateIds = (_idMode == 2);
            widget.project.generatedIdPrefix = _idMode == 2
                ? _prefixCtrl.text.trim()
                : null;
            widget.project.snapMode = _snapMode;
            widget.project.snapOffset = newSnapOffset;

            if (mounted) {
              Navigator.of(
                context,
              ).pop(ProjectSettingsResult(settingsChanged, applyRetroactively));
            }
          },
          child: const Text("Save"),
        ),
      ],
    );
  }
}
