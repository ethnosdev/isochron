import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:isochron_flutter/services/export_service.dart';
import 'package:isochron_flutter/ui/components/macos_dialogs.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:isochron_flutter/ui/theme/app_theme.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path/path.dart' as p;

typedef DirectoryPickerFn = Future<String?> Function({
  String? dialogTitle,
  String? initialDirectory,
});

typedef FileSaverFn = Future<String?> Function({
  String? dialogTitle,
  String? fileName,
  FileType type,
  List<String>? allowedExtensions,
  String? initialDirectory,
});

class GroupExportResult {
  final bool success;
  final String message;

  const GroupExportResult({required this.success, required this.message});
}

class GroupExportDialog extends StatefulWidget {
  final Project project;
  final Collection? collection;
  final DirectoryPickerFn? directoryPicker;
  final FileSaverFn? fileSaver;

  const GroupExportDialog({
    super.key,
    required this.project,
    this.collection,
    this.directoryPicker,
    this.fileSaver,
  });

  static Future<void> show(
    BuildContext context, {
    required Project project,
    Collection? collection,
    DirectoryPickerFn? directoryPicker,
    FileSaverFn? fileSaver,
  }) async {
    final result = await showAppSheet<GroupExportResult>(
      context: context,
      barrierDismissible: true,
      builder: (_) => MacosSheet(
        child: SizedBox(
          width: 520,
          child: GroupExportDialog(
            project: project,
            collection: collection,
            directoryPicker: directoryPicker,
            fileSaver: fileSaver,
          ),
        ),
      ),
    );

    if (result != null && context.mounted) {
      if (result.success) {
        showAppAlertDialog(
          context: context,
          barrierLabel: 'Dismiss',
          builder: (ctx) => MacosAlertDialog(
            appIcon: const MacosIcon(CupertinoIcons.checkmark_seal_fill),
            title: const Text('Export Complete'),
            message: Text(result.message, textAlign: TextAlign.center),
            primaryButton: PushButton(
              controlSize: ControlSize.large,
              child: const Text('OK'),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ),
        );
      } else {
        showAppAlertDialog(
          context: context,
          barrierLabel: 'Dismiss',
          builder: (ctx) => MacosAlertDialog(
            appIcon:
                const MacosIcon(CupertinoIcons.exclamationmark_triangle_fill),
            title: const Text('Export Failed'),
            message: Text(result.message, textAlign: TextAlign.center),
            primaryButton: PushButton(
              controlSize: ControlSize.large,
              child: const Text('OK'),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ),
        );
      }
    }
  }

  @override
  State<GroupExportDialog> createState() => _GroupExportDialogState();
}

class _GroupExportDialogState extends State<GroupExportDialog> {
  GroupExportMode _selectedMode = GroupExportMode.separateFiles;
  bool _isExporting = false;

  List<Track> get _allTracks => widget.collection != null
      ? widget.collection!.tracks
      : [for (final c in widget.project.collections) ...c.tracks];

  List<Track> get _readyTracks =>
      _allTracks.where(ExportService.canExportPhraseTiming).toList();

  Future<void> _handleExport() async {
    setState(() => _isExporting = true);
    try {
      if (_selectedMode == GroupExportMode.separateFiles) {
        final picker = widget.directoryPicker ?? FilePicker.getDirectoryPath;
        final selectedDir = await picker(
          dialogTitle: 'Select Destination Folder for Export',
          initialDirectory: widget.project.directoryPath,
        );
        if (selectedDir == null) {
          if (mounted) setState(() => _isExporting = false);
          return;
        }

        final int count;
        if (widget.collection != null) {
          count = await ExportService.exportDividedChaptersToDirectory(
            widget.project,
            widget.collection!.tracks,
            selectedDir,
          );
        } else {
          count = await ExportService.exportProjectDividedChaptersToDirectory(
            widget.project,
            selectedDir,
          );
        }

        if (mounted) {
          Navigator.of(context).pop(
            GroupExportResult(
              success: true,
              message:
                  'Successfully exported $count timing file(s) to:\n$selectedDir',
            ),
          );
        }
      } else if (_selectedMode == GroupExportMode.singleFile) {
        final saver = widget.fileSaver ?? FilePicker.saveFile;
        final defaultName = widget.collection != null
            ? '${widget.collection!.folderName}-timing.txt'
            : '${widget.project.name}-timing.txt';
        final outputFile = await saver(
          dialogTitle: 'Save Timing File',
          fileName: defaultName,
          type: FileType.custom,
          allowedExtensions: ['txt'],
          initialDirectory: widget.project.directoryPath,
        );
        if (outputFile == null) {
          if (mounted) setState(() => _isExporting = false);
          return;
        }

        final targetPath =
            outputFile.endsWith('.txt') ? outputFile : '$outputFile.txt';
        final payload =
            await ExportService.buildDividedChaptersSingleFilePayload(
          widget.project,
          _readyTracks,
        );

        if (payload != null) {
          await File(targetPath).writeAsString(payload);
        }

        if (mounted) {
          Navigator.of(context).pop(
            GroupExportResult(
              success: true,
              message:
                  'Successfully exported timing file to:\n${p.basename(targetPath)}',
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(
          GroupExportResult(
            success: false,
            message: e.toString(),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Widget _buildModeOption({
    required BuildContext context,
    required GroupExportMode mode,
    required String title,
    required String subtitle,
  }) {
    final theme = MacosTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isSelected = _selectedMode == mode;

    final unselectedBg =
        isDark ? const Color(0xFF2A2A2A) : const Color(0xFFFFFFFF);
    final selectedBg = isDark
        ? theme.primaryColor.withValues(alpha: 0.20)
        : theme.primaryColor.withValues(alpha: 0.08);

    final borderColor = isSelected ? theme.primaryColor : theme.dividerColor;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          _selectedMode = mode;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? selectedBg : unselectedBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: borderColor,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: MacosRadioButton<GroupExportMode>(
                value: mode,
                groupValue: _selectedMode,
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedMode = val);
                  }
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: isSelected
                          ? (isDark ? AppTheme.darkAccent : theme.primaryColor)
                          : theme.typography.body.color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.grey(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isProject = widget.collection == null;
    final totalCount = _allTracks.length;
    final readyCount = _readyTracks.length;
    final unalignedCount = totalCount - readyCount;

    final String statusMessage;
    if (totalCount == 0) {
      statusMessage =
          'No tracks found in this ${isProject ? 'project' : 'collection'}.';
    } else if (readyCount == 0) {
      statusMessage =
          'None of the $totalCount track(s) have finished alignment. Run alignment on tracks before exporting.';
    } else if (unalignedCount > 0) {
      statusMessage =
          '$readyCount of $totalCount track(s) are ready to export. $unalignedCount unaligned track(s) will be skipped.';
    } else {
      statusMessage =
          'All $totalCount track(s) are aligned and ready to export.';
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isProject
                      ? 'Export Project Timings'
                      : 'Export Collection Timings',
                  style: theme.typography.headline,
                ),
                MacosIconButton(
                  icon: const MacosIcon(CupertinoIcons.xmark_circle),
                  onPressed:
                      _isExporting ? null : () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              isProject
                  ? 'Export phrase timings for all collections in "${widget.project.name}".'
                  : 'Export phrase timings for collection "${widget.collection!.name}".',
              style: theme.typography.subheadline,
            ),
            const SizedBox(height: 12),

            // Status Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF2A2A2A)
                    : const Color(0xFFFFFFFF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.dividerColor),
              ),
              child: Row(
                children: [
                  Icon(
                    readyCount == 0
                        ? CupertinoIcons.exclamationmark_triangle_fill
                        : (unalignedCount > 0
                            ? CupertinoIcons.info_circle_fill
                            : CupertinoIcons.checkmark_circle_fill),
                    color: readyCount == 0
                        ? AppTheme.destructive(context)
                        : (unalignedCount > 0
                            ? AppTheme.warning(context)
                            : AppTheme.success(context)),
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      statusMessage,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            Text(
              'Export Format',
              style:
                  theme.typography.body.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            _buildModeOption(
              context: context,
              mode: GroupExportMode.separateFiles,
              title: 'Separate files',
              subtitle: isProject && widget.project.collections.length > 1
                  ? 'Exports each track as its own .txt file into collection subfolders in a selected directory.'
                  : 'Exports each track as its own .txt file into a selected directory.',
            ),
            _buildModeOption(
              context: context,
              mode: GroupExportMode.singleFile,
              title: 'Single file',
              subtitle:
                  'Combines all tracks into one .txt file with separate chapter headers (\\c 1, \\c 2, ...).',
            ),
            const SizedBox(height: 16),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                PushButton(
                  controlSize: ControlSize.large,
                  secondary: true,
                  onPressed:
                      _isExporting ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                PushButton(
                  controlSize: ControlSize.large,
                  onPressed:
                      (readyCount > 0 && !_isExporting) ? _handleExport : null,
                  child: _isExporting
                      ? const ProgressCircle(radius: 8)
                      : const Text('Export...'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
