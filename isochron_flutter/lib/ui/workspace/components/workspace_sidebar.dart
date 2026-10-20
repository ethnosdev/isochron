import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:isochron_flutter/services/export_service.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'package:isochron_flutter/ui/components/macos_context_menu.dart';
import 'package:isochron_flutter/ui/components/macos_dialogs.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:isochron_flutter/ui/settings/model_panel.dart';
import 'package:isochron_flutter/ui/theme/app_theme.dart';
import 'package:isochron_flutter/ui/workspace/components/group_export_dialog.dart';
import 'package:isochron_flutter/ui/workspace/components/inline_text_editor.dart';
import 'package:isochron_flutter/ui/workspace/models/sidebar_node.dart';
import 'package:isochron_flutter/ui/workspace/models/workspace_models.dart';
import 'package:isochron_flutter/ui/workspace/workspace_manager.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path/path.dart' as p;

Sidebar buildWorkspaceSidebar(
  BuildContext context,
  WorkspaceManager manager,
) {
  final theme = MacosTheme.of(context);
  final flatNodes = _getFlatNodes(manager);

  return Sidebar(
    minWidth: 220,
    startWidth: 260,
    maxWidth: 350,
    top: Padding(
      padding: const EdgeInsets.only(
        left: 16.0,
        right: 8.0,
        top: 12.0,
        bottom: 8.0,
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onSecondaryTapDown: (details) {
                if (manager.project == null) return;
                showMacosContextMenu(
                  context: context,
                  position: details.globalPosition,
                  items: [
                    MacosContextMenuItem(
                      title: "Rename Project...",
                      icon: CupertinoIcons.pencil,
                      onTap: () => _promptRenameProject(context, manager),
                    ),
                    MacosContextMenuItem(
                      title: "Reveal in Finder",
                      icon: CupertinoIcons.folder,
                      onTap: () =>
                          _revealInFinder(manager.project!.directoryPath),
                    ),
                    MacosContextMenuItem(
                      title: "Project Settings",
                      icon: CupertinoIcons.gear_alt,
                      onTap: () => manager.selectNode(
                        TreeSelection(type: NodeType.settings),
                      ),
                    ),
                  ],
                );
              },
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      manager.project?.name ?? '',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  MacosTooltip(
                    message: "Rename Project",
                    child: MacosIconButton(
                      icon: MacosIcon(
                        CupertinoIcons.pencil,
                        size: 13,
                        color: AppTheme.grey(context),
                      ),
                      boxConstraints: const BoxConstraints(
                        minHeight: 20,
                        minWidth: 20,
                      ),
                      padding: const EdgeInsets.all(2),
                      onPressed: () => _promptRenameProject(context, manager),
                    ),
                  ),
                ],
              ),
            ),
          ),
          MacosTooltip(
            message: "New Collection",
            child: MacosIconButton(
              icon: MacosIcon(
                CupertinoIcons.folder_badge_plus,
                size: 18,
                color: theme.typography.body.color,
              ),
              onPressed: manager.addCollection,
              boxConstraints: const BoxConstraints(minHeight: 28, minWidth: 28),
            ),
          ),
        ],
      ),
    ),
    bottom: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Row(
        children: [
          MacosTooltip(
            message: "Project Settings",
            child: MacosIconButton(
              icon: MacosIcon(
                CupertinoIcons.gear_alt,
                size: 16,
                color: theme.typography.body.color,
              ),
              boxConstraints: const BoxConstraints(minHeight: 28, minWidth: 28),
              onPressed: () {
                manager.selectNode(TreeSelection(type: NodeType.settings));
              },
            ),
          ),
          const SizedBox(width: 8),
          MacosTooltip(
            message: "Acoustic Model",
            child: MacosIconButton(
              icon: MacosIcon(
                CupertinoIcons.waveform_circle,
                size: 16,
                color: theme.typography.body.color,
              ),
              boxConstraints: const BoxConstraints(minHeight: 28, minWidth: 28),
              onPressed: () => ModelPanel.show(context),
            ),
          ),
        ],
      ),
    ),
    builder: (context, scrollController) => ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: flatNodes.length,
      itemBuilder: (context, index) {
        return _buildTreeRowForNode(
          context,
          manager,
          flatNodes[index],
        );
      },
    ),
  );
}

// ---------------------------------------------------------------------------
// HELPER FUNCTIONS
// ---------------------------------------------------------------------------

List<SidebarNode> _getFlatNodes(WorkspaceManager manager) {
  if (manager.project == null) return const [];
  final List<SidebarNode> nodes = [];

  for (final col in manager.project!.collections) {
    nodes.add(
      SidebarNode(
        id: col.id,
        type: SidebarNodeType.collection,
        collection: col,
        depth: 0,
      ),
    );

    if (manager.expandedNodes.contains(col.id)) {
      for (final track in col.tracks) {
        nodes.add(
          SidebarNode(
            id: track.id,
            type: SidebarNodeType.track,
            collection: col,
            track: track,
            depth: 1,
          ),
        );
      }
    }
  }
  return nodes;
}

Color _getTrackColor(BuildContext context, AlignmentStatus status) {
  switch (status) {
    case AlignmentStatus.done:
    case AlignmentStatus.reviewed:
      return AppTheme.success(context);
    case AlignmentStatus.processing:
      return AppTheme.accent(context);
    case AlignmentStatus.error:
      return AppTheme.destructive(context);
    case AlignmentStatus.pending:
      return AppTheme.warning(context);
  }
}

void _revealInFinder(String path) {
  final target = File(path).existsSync()
      ? path
      : (Directory(path).existsSync() ? path : p.dirname(path));
  if (Platform.isMacOS) {
    Process.run('open', ['-R', target]);
  } else if (Platform.isWindows) {
    Process.run('explorer.exe', ['/select,', target]);
  } else {
    Process.run('xdg-open', [p.dirname(target)]);
  }
}

Future<void> _handleExportPhraseTimingForTrack(
  BuildContext context,
  WorkspaceManager manager,
  Track track,
) async {
  if (manager.project == null || !ExportService.canExportPhraseTiming(track)) {
    return;
  }

  final defaultName = ExportService.defaultPhraseTimingFilenameForTrack(track);
  final outputFile = await FilePicker.saveFile(
    dialogTitle: 'Export Phrase Timing',
    fileName: defaultName,
    type: FileType.custom,
    allowedExtensions: ['txt'],
    initialDirectory: manager.project!.directoryPath,
  );

  if (outputFile == null) return;

  try {
    final payload = await ExportService.buildPhraseTiming(
      manager.project!,
      track,
    );
    if (payload != null && payload.isNotEmpty) {
      await File(outputFile).writeAsString(payload);
    }
  } catch (e) {
    if (context.mounted) {
      showCupertinoDialog(
        context: context,
        builder: (_) => CupertinoAlertDialog(
          title: const Text("Export Error"),
          content: Text(e.toString()),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              child: const Text("OK"),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
    }
  }
}


Widget _buildTreeRowForNode(
  BuildContext context,
  WorkspaceManager manager,
  SidebarNode node,
) {
  final theme = MacosTheme.of(context);

  switch (node.type) {
    case SidebarNodeType.collection:
      final col = node.collection!;
      final isColSelected =
          manager.selectedNode?.collection == col &&
          manager.selectedNode?.type == NodeType.collection;

      return _buildTreeRow(
        context: context,
        label: col.name,
        icon: isColSelected
            ? CupertinoIcons.folder_solid
            : CupertinoIcons.folder,
        iconColor: theme.typography.body.color ?? CupertinoColors.black,
        isSelected: isColSelected,
        isExpanded: manager.expandedNodes.contains(col.id),
        depth: 0,
        hasChildren: true,
        isEditing: manager.editingNodeId == col.id,
        onToggleExpand: () => manager.toggleExpandedNode(col.id),
        onDoubleTap: () => manager.toggleExpandedNode(col.id),
        onEditComplete: (newName) => manager.renameCollection(col, newName),
        onSecondaryTapDown: (details) {
          final colDir = p.join(
            manager.project!.directoryPath,
            'collections',
            col.folderName,
          );
          showMacosContextMenu(
            context: context,
            position: details.globalPosition,
            items: [
              MacosContextMenuItem(
                title: "Rename",
                icon: CupertinoIcons.pencil,
                onTap: () => manager.setEditingNode(col.id),
              ),
              MacosContextMenuItem(
                title: "Add & Pair Media...",
                icon: CupertinoIcons.arrow_down_doc,
                onTap: () => manager.openTrackPairingWizard(context, col),
              ),
              MacosContextMenuItem(
                title: "Run Alignment on All",
                icon: CupertinoIcons.play_arrow_solid,
                onTap: () => manager.runBatch(col),
              ),
              MacosContextMenuItem(
                title: "Export Timings...",
                icon: CupertinoIcons.square_arrow_down,
                onTap: () => GroupExportDialog.show(
                  context,
                  project: manager.project!,
                  collection: col,
                ),
              ),
              const MacosContextMenuDivider(),
              MacosContextMenuItem(
                title: "Reveal in Finder",
                icon: CupertinoIcons.folder,
                onTap: () => _revealInFinder(colDir),
              ),
              const MacosContextMenuDivider(),
              MacosContextMenuItem(
                title: "Delete Collection",
                icon: CupertinoIcons.trash,
                isDestructive: true,
                onTap: () => manager.deleteCollection(col),
              ),
            ],
          );
        },
        onTap: () async {
          if (manager.editingNodeId != null) {
            manager.setEditingNode(null);
            return;
          }

          await manager.homeManager.flushPendingAutoSave();

          manager.selectNode(
            TreeSelection(type: NodeType.collection, collection: col),
          );
        },
      );

    case SidebarNodeType.track:
      final track = node.track!;
      final col = node.collection!;
      final isTrackSelected =
          manager.selectedNode?.track == track &&
          manager.selectedNode?.type == NodeType.track;

      final resolvedAudio = track.getResolvedAudioPath(
        manager.project!.directoryPath,
        col.folderName,
      );
      final resolvedText = track.getResolvedTextPath(
        manager.project!.directoryPath,
        col.folderName,
      );

      final bool audioMissing =
          resolvedAudio == null || !File(resolvedAudio).existsSync();
      final bool textMissing =
          resolvedText == null || !File(resolvedText).existsSync();
      final bool isMissing = audioMissing || textMissing;

      Widget? trailingWidget;
      if (isMissing) {
        trailingWidget = MacosTooltip(
          message: audioMissing && textMissing
              ? "Missing audio and transcript files"
              : audioMissing
                  ? "Missing audio file"
                  : "Missing transcript file",
          child: Icon(
            CupertinoIcons.exclamationmark_triangle_fill,
            size: 14,
            color: AppTheme.destructive(context),
          ),
        );
      }

      return _buildTreeRow(
        context: context,
        label: track.name,
        icon: CupertinoIcons.waveform_path,
        iconColor: _getTrackColor(context, track.status),
        isSelected: isTrackSelected,
        isExpanded: false,
        depth: 1,
        hasChildren: false,
        isEditing: manager.editingNodeId == track.id,
        trailing: trailingWidget,
        onDoubleTap: () => manager.setEditingNode(track.id),
        onEditComplete: (newName) => manager.renameTrack(track, col, newName),
        onSecondaryTapDown: (details) {
          final targetPath = resolvedAudio ?? resolvedText ?? p.join(
            manager.project!.directoryPath,
            'collections',
            col.folderName,
          );
          showMacosContextMenu(
            context: context,
            position: details.globalPosition,
            items: [
              MacosContextMenuItem(
                title: "Rename",
                icon: CupertinoIcons.pencil,
                onTap: () => manager.setEditingNode(track.id),
              ),
              MacosContextMenuItem(
                title: "Run Auto-Align",
                icon: CupertinoIcons.play_arrow_solid,
                onTap: () {
                  manager.selectNode(
                    TreeSelection(
                      type: NodeType.track,
                      collection: col,
                      track: track,
                    ),
                  );
                  manager.loadTrackInEditor(track);
                  manager.homeManager.runAlignment(
                    trackId: track.id,
                    languageCode: manager.project?.languageCode,
                  );
                },
              ),
              MacosContextMenuItem(
                title: "Export Timing...",
                icon: CupertinoIcons.square_arrow_down,
                enabled: ExportService.canExportPhraseTiming(track),
                onTap: () => _handleExportPhraseTimingForTrack(
                  context,
                  manager,
                  track,
                ),
              ),
              const MacosContextMenuDivider(),
              MacosContextMenuItem(
                title: "Replace Audio File...",
                icon: CupertinoIcons.speaker_2_fill,
                onTap: () async {
                  final settings = UserSettingsService();
                  final picked = await FilePicker.pickFiles(
                    type: FileType.audio,
                    initialDirectory: settings.lastSourceDir,
                  );
                  if (picked != null && picked.files.single.path != null) {
                    final pickedPath = picked.files.single.path!;
                    settings.setLastSourceDir(p.dirname(pickedPath));
                    await manager.replaceTrackAudio(track, col, pickedPath);
                  }
                },
              ),
              MacosContextMenuItem(
                title: "Replace Transcript File...",
                icon: CupertinoIcons.doc_text_fill,
                onTap: () async {
                  final settings = UserSettingsService();
                  final picked = await FilePicker.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['txt', 'phrases'],
                    initialDirectory: settings.lastSourceDir,
                  );
                  if (picked != null && picked.files.single.path != null) {
                    final pickedPath = picked.files.single.path!;
                    settings.setLastSourceDir(p.dirname(pickedPath));
                    await manager.replaceTrackText(track, col, pickedPath);
                  }
                },
              ),
              const MacosContextMenuDivider(),
              MacosContextMenuItem(
                title: "Reveal in Finder",
                icon: CupertinoIcons.folder,
                onTap: () => _revealInFinder(targetPath),
              ),
              const MacosContextMenuDivider(),
              MacosContextMenuItem(
                title: "Delete Track",
                icon: CupertinoIcons.trash,
                isDestructive: true,
                onTap: () => manager.deleteTrack(track, col),
              ),
            ],
          );
        },
        onTap: () async {
          if (manager.editingNodeId != null) {
            manager.setEditingNode(null);
            return;
          }

          await manager.homeManager.flushPendingAutoSave();

          manager.selectNode(
            TreeSelection(type: NodeType.track, collection: col, track: track),
          );
          manager.loadTrackInEditor(track);
        },
      );
  }
}

Widget _buildTreeRow({
  required BuildContext context,
  required String label,
  required IconData icon,
  required Color iconColor,
  required bool isSelected,
  required bool isExpanded,
  required int depth,
  required bool hasChildren,
  required VoidCallback onTap,
  VoidCallback? onToggleExpand,
  VoidCallback? onDoubleTap,
  void Function(TapDownDetails)? onSecondaryTapDown,
  bool isEditing = false,
  ValueChanged<String>? onEditComplete,
  Widget? trailing,
}) {
  final theme = MacosTheme.of(context);
  final selectionBg = AppTheme.selectionBg(context);

  return GestureDetector(
    onTap: onTap,
    onDoubleTap: onDoubleTap,
    onSecondaryTapDown: onSecondaryTapDown,
    behavior: HitTestBehavior.opaque,
    child: Container(
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      padding: EdgeInsets.only(left: depth * 16.0 + 8.0, right: 8.0),
      decoration: BoxDecoration(
        color: isSelected ? selectionBg : CupertinoColors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          if (hasChildren)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggleExpand,
              child: Padding(
                padding: const EdgeInsets.all(2.0),
                child: Icon(
                  isExpanded
                      ? CupertinoIcons.chevron_down
                      : CupertinoIcons.chevron_right,
                  size: 12,
                  color: isSelected
                      ? AppTheme.selectionText(context)
                      : CupertinoColors.systemGrey,
                ),
              ),
            )
          else
            const SizedBox(width: 16),
          const SizedBox(width: 4),
          Icon(
            icon,
            size: 14,
            color: isSelected ? AppTheme.selectionText(context) : iconColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: isEditing
                ? InlineTextEditor(
                    initialText: label,
                    onComplete: onEditComplete!,
                  )
                : Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected
                          ? AppTheme.selectionText(context)
                          : theme.typography.body.color,
                    ),
                  ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 6),
            trailing,
          ],
        ],
      ),
    ),
  );
}

void _promptRenameProject(BuildContext context, WorkspaceManager manager) {
  if (manager.project == null) return;
  final controller = TextEditingController(text: manager.project!.name);
  showAppAlertDialog(
    context: context,
    builder: (ctx) => MacosAlertDialog(
      appIcon: const MacosIcon(CupertinoIcons.pencil_circle),
      title: const Text('Rename Project'),
      message: Column(
        children: [
          const Text('Enter a new name for this project:'),
          const SizedBox(height: 12),
          MacosTextField(
            controller: controller,
            autofocus: true,
            onSubmitted: (val) {
              Navigator.of(ctx).pop(val);
            },
          ),
        ],
      ),
      primaryButton: PushButton(
        controlSize: ControlSize.large,
        onPressed: () => Navigator.of(ctx).pop(controller.text),
        child: const Text('Rename'),
      ),
      secondaryButton: PushButton(
        controlSize: ControlSize.large,
        secondary: true,
        onPressed: () => Navigator.of(ctx).pop(),
        child: const Text('Cancel'),
      ),
    ),
  ).then((newName) {
    if (newName != null && newName is String && newName.trim().isNotEmpty) {
      manager.renameProject(newName.trim());
    }
  });
}
