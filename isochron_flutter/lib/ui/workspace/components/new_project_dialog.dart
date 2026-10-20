import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'package:isochron_flutter/ui/components/macos_dialogs.dart';
import 'package:isochron_flutter/ui/theme/app_theme.dart';
import 'package:isochron_flutter/ui/workspace/components/track_pairing_wizard.dart';
import 'package:isochron_flutter/utils/media_pairing_engine.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class NewProjectResult {
  final String projectPath;
  final String projectName;
  final String collectionName;
  final List<PairedRow>? initialTracks;

  const NewProjectResult({
    required this.projectPath,
    required this.projectName,
    required this.collectionName,
    this.initialTracks,
  });
}

class NewProjectDialog extends StatefulWidget {
  const NewProjectDialog({super.key});

  static Future<NewProjectResult?> show(BuildContext context) {
    return showAppSheet<NewProjectResult>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const MacosSheet(
        child: SizedBox(
          width: 520,
          child: NewProjectDialog(),
        ),
      ),
    );
  }

  @override
  State<NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<NewProjectDialog> {
  final TextEditingController _nameController =
      TextEditingController(text: 'My Project');
  final TextEditingController _collectionController =
      TextEditingController(text: 'Main');

  String _parentDirectory = '';
  bool _isLoadingDir = true;
  List<PairedRow>? _stagedTracks;

  @override
  void initState() {
    super.initState();
    _initParentDirectory();
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _collectionController.dispose();
    super.dispose();
  }

  Future<void> _initParentDirectory() async {
    final settings = UserSettingsService();
    String? dir = settings.lastProjectDir;
    if (dir == null || !Directory(dir).existsSync()) {
      try {
        final docs = await getApplicationDocumentsDirectory();
        dir = docs.path;
      } catch (_) {
        dir = Directory.current.path;
      }
    }
    if (mounted) {
      setState(() {
        _parentDirectory = dir!;
        _isLoadingDir = false;
      });
    }
  }

  Future<void> _pickParentDirectory() async {
    final picked = await FilePicker.getDirectoryPath(
      dialogTitle: 'Select Location for Project Folder',
      initialDirectory: _parentDirectory,
    );
    if (picked != null && mounted) {
      setState(() {
        _parentDirectory = picked;
      });
    }
  }

  String get _projectName => _nameController.text.trim();
  String get _collectionName =>
      _collectionController.text.trim().isEmpty ? 'Main' : _collectionController.text.trim();

  String get _targetProjectPath =>
      _projectName.isNotEmpty ? p.join(_parentDirectory, _projectName) : '';

  bool get _folderAlreadyExists =>
      _targetProjectPath.isNotEmpty && Directory(_targetProjectPath).existsSync();

  bool get _canCreate =>
      !_isLoadingDir &&
      _projectName.isNotEmpty &&
      _parentDirectory.isNotEmpty &&
      !_folderAlreadyExists;

  void _handleCreate() {
    if (!_canCreate) return;
    Navigator.of(context).pop(
      NewProjectResult(
        projectPath: _targetProjectPath,
        projectName: _projectName,
        collectionName: _collectionName,
        initialTracks: _stagedTracks,
      ),
    );
  }

  Future<void> _handleNextAddTracks() async {
    if (!_canCreate) return;
    final result = await TrackPairingWizard.show(
      context,
      collectionName: _collectionName,
      initialAudioFiles: _stagedTracks
          ?.where((r) => r.audioPath != null)
          .map((r) => r.audioPath!)
          .toList(),
      initialTextFiles: _stagedTracks
          ?.where((r) => r.textPath != null)
          .map((r) => r.textPath!)
          .toList(),
    );

    if (result != null && mounted) {
      setState(() {
        _stagedTracks = result.rows;
      });
      // Automatically proceed to create project with these staged tracks
      _handleCreate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final textFieldDecoration = BoxDecoration(
      color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFFFFFFF),
      border: Border.all(color: theme.dividerColor),
      borderRadius: BorderRadius.circular(6.0),
    );

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Create New Project',
                  style: theme.typography.headline,
                ),
                MacosIconButton(
                  icon: const MacosIcon(CupertinoIcons.xmark_circle),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Set up a new alignment project with an initial collection.',
              style: theme.typography.subheadline,
            ),
            const SizedBox(height: 20),

            // Project Name Field
            Text(
              'Project Name',
              style: theme.typography.body.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            MacosTextField(
              controller: _nameController,
              autofocus: true,
              placeholder: 'e.g. BSB, John Gospel, etc.',
              decoration: textFieldDecoration,
              onSubmitted: (_) => _handleCreate(),
            ),
            const SizedBox(height: 16),

            // Initial Collection Name Field
            Text(
              'First Collection Name',
              style: theme.typography.body.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            MacosTextField(
              controller: _collectionController,
              placeholder: 'e.g. NT, OT, Chapter 1, etc.',
              decoration: textFieldDecoration,
              onSubmitted: (_) => _handleCreate(),
            ),
            const SizedBox(height: 16),

            // Location Section
            Text(
              'Location',
              style: theme.typography.body.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF222222)
                          : const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Text(
                      _parentDirectory.isEmpty ? 'Loading...' : _parentDirectory,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                PushButton(
                  controlSize: ControlSize.regular,
                  secondary: true,
                  onPressed: _pickParentDirectory,
                  child: const Text('Browse...'),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Preview Path / Warnings
            if (_folderAlreadyExists) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    CupertinoIcons.exclamationmark_triangle_fill,
                    size: 14,
                    color: AppTheme.destructive(context),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'A folder named "$_projectName" already exists in this location.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.destructive(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ] else if (_targetProjectPath.isNotEmpty) ...[
              Text(
                'Will be created at: $_targetProjectPath',
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppTheme.grey(context),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 24),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                PushButton(
                  controlSize: ControlSize.large,
                  secondary: true,
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 10),
                PushButton(
                  controlSize: ControlSize.large,
                  secondary: true,
                  onPressed: _canCreate ? _handleNextAddTracks : null,
                  child: const Text('Next: Add Tracks...'),
                ),
                const SizedBox(width: 10),
                PushButton(
                  controlSize: ControlSize.large,
                  onPressed: _canCreate ? _handleCreate : null,
                  child: const Text('Create Project'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
