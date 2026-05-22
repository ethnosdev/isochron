import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:file_picker/file_picker.dart';
import 'package:isochron_flutter/services/export_service.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:isochron_flutter/ui/workspace/models/workspace_models.dart';
import 'package:isochron_flutter/ui/workspace/workspace_manager.dart';
import 'package:macos_ui/macos_ui.dart';

ToolBar buildWorkspaceToolbar(BuildContext context, WorkspaceManager manager) {
  final selectedNode = manager.selectedNode;

  Future<void> requestDeleteCollection(Collection collection) async {
    final bool? confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Delete Collection?'),
        content: Text(
          'Are you sure you want to delete "${collection.name}" and all of its tracks?\n\nThis will remove them from the project, but your raw audio and text files will remain safe on your hard drive.',
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await manager.deleteCollection(collection);
    }
  }

  Future<void> requestDeleteTrack(Track track, Collection collection) async {
    final bool? confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Delete Track?'),
        content: Text(
          'Are you sure you want to remove "${track.name}" from this collection?',
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await manager.deleteTrack(track, collection);
    }
  }

  Future<void> handleExportPhraseTimingForTrack(Track track) async {
    if (manager.project == null || !ExportService.canExportPhraseTiming(track))
      return;

    final defaultName = ExportService.defaultPhraseTimingFilenameForTrack(
      track,
    );
    final outputFile = await FilePicker.saveFile(
      dialogTitle: 'Export Phrase Timing',
      fileName: defaultName,
      type: FileType.custom,
      allowedExtensions: ['txt'],
      initialDirectory: manager.project!.directoryPath,
    );

    if (outputFile == null) return;

    final payload = await ExportService.buildPhraseTiming(
      manager.project!,
      track,
    );
    if (payload != null && payload.isNotEmpty) {
      await File(outputFile).writeAsString(payload);
    }
  }

  return ToolBar(
    title: Text(
      selectedNode?.type == NodeType.track
          ? selectedNode!.track!.name
          : (selectedNode?.type == NodeType.settings
                ? "Settings"
                : "Isochron Studio"),
    ),
    actions: [
      // --- TRACK ACTIONS ---
      if (selectedNode?.type == NodeType.track) ...[
        ToolBarIconButton(
          label: 'Save',
          icon: MacosIcon(
            CupertinoIcons.floppy_disk,
            color: manager.hasUnsavedChanges
                ? MacosTheme.of(context).typography.body.color
                : CupertinoColors.systemGrey.withValues(alpha: 0.5),
          ),
          showLabel: true,
          onPressed: manager.hasUnsavedChanges ? manager.saveProject : null,
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
              await manager.homeManager.runAlignment(
                trackId: selectedNode!.track!.id,
                snapMode: manager.project!.snapMode,
                snapOffsetMs: manager.project!.snapOffset ?? 0,
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
        ToolBarIconButton(
          label: 'Export Timing',
          icon: MacosIcon(
            CupertinoIcons.square_arrow_down,
            color: ExportService.canExportPhraseTiming(selectedNode!.track!)
                ? MacosTheme.of(context).typography.body.color
                : CupertinoColors.systemGrey.withValues(alpha: 0.5),
          ),
          showLabel: true,
          tooltipMessage: ExportService.phraseExportTooltip(
            selectedNode.track!,
          ),
          onPressed: ExportService.canExportPhraseTiming(selectedNode.track!)
              ? () => handleExportPhraseTimingForTrack(selectedNode.track!)
              : null,
        ),
        ToolBarIconButton(
          label: 'Zoom Out',
          icon: MacosIcon(
            CupertinoIcons.zoom_out,
            color: MacosTheme.of(context).typography.body.color,
          ),
          showLabel: false,
          tooltipMessage: 'Zoom Out',
          onPressed: () => manager.homeManager.setZoom(
            manager.homeManager.value.zoomLevel / 1.5,
          ),
        ),
        ToolBarIconButton(
          label: 'Zoom In',
          icon: MacosIcon(
            CupertinoIcons.zoom_in,
            color: MacosTheme.of(context).typography.body.color,
          ),
          showLabel: false,
          tooltipMessage: 'Zoom In',
          onPressed: () => manager.homeManager.setZoom(
            manager.homeManager.value.zoomLevel * 1.5,
          ),
        ),
        const ToolBarSpacer(),
        ToolBarIconButton(
          label: 'Delete Track',
          icon: const MacosIcon(
            CupertinoIcons.trash,
            color: CupertinoColors.destructiveRed,
          ),
          showLabel: false,
          tooltipMessage: 'Delete Track',
          onPressed: () =>
              requestDeleteTrack(selectedNode.track!, selectedNode.collection!),
        ),
      ]
      // --- COLLECTION ACTIONS ---
      else if (selectedNode?.type == NodeType.collection) ...[
        const ToolBarSpacer(),
        ToolBarIconButton(
          label: 'Delete Collection',
          icon: const MacosIcon(
            CupertinoIcons.trash,
            color: CupertinoColors.destructiveRed,
          ),
          showLabel: true,
          tooltipMessage: 'Delete Collection',
          onPressed: () => requestDeleteCollection(selectedNode!.collection!),
        ),
      ],
    ],
  );
}
