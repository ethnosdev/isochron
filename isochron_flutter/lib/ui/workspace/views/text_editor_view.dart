import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path/path.dart' as p;

class TextEditorView extends StatefulWidget {
  final Track track;
  final Project project;
  final Collection collection;
  final Future<void> Function(Future<void> Function()) onReplaceOrEdit;

  const TextEditorView({
    super.key,
    required this.track,
    required this.project,
    required this.collection,
    required this.onReplaceOrEdit,
  });

  @override
  State<TextEditorView> createState() => _TextEditorViewState();
}

class _TextEditorViewState extends State<TextEditorView> {
  late TextEditingController _controller;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _loadFile();
  }

  Future<void> _loadFile() async {
    final resolvedPath = widget.track.getResolvedTextPath(
      widget.project.directoryPath,
      widget.collection.folderName,
    );
    if (resolvedPath != null && await File(resolvedPath).exists()) {
      _controller.text = await File(resolvedPath).readAsString();
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

    final resolvedPath = widget.track.getResolvedTextPath(
      widget.project.directoryPath,
      widget.collection.folderName,
    )!;

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
                      await File(resolvedPath).writeAsString(_controller.text);
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
    final settings = UserSettingsService();
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'phrases'],
      initialDirectory: settings.lastSourceDir,
    );
    if (result != null && result.files.single.path != null) {
      final originalPath = result.files.single.path!;
      settings.setLastSourceDir(p.dirname(originalPath));

      widget.onReplaceOrEdit(() async {
        if (widget.project.copyMediaIntoProject) {
          final textDir = Directory(
            p.join(
              widget.project.directoryPath,
              'collections',
              widget.collection.folderName,
              'text',
            ),
          );
          if (!await textDir.exists()) await textDir.create(recursive: true);
          final newPath = p.join(textDir.path, p.basename(originalPath));
          await File(originalPath).copy(newPath);
          widget.track.textPath = p.basename(originalPath);
        } else {
          widget.track.textPath = originalPath;
        }
        await _loadFile();
      });
    }
  }
}
