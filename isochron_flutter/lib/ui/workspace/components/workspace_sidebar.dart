import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:isochron_flutter/ui/workspace/components/inline_text_editor.dart';
import 'package:isochron_flutter/ui/workspace/models/sidebar_node.dart';
import 'package:isochron_flutter/ui/workspace/models/workspace_models.dart';
import 'package:isochron_flutter/ui/workspace/workspace_manager.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path/path.dart' as p;
import 'package:isochron_flutter/ui/theme/app_theme.dart';

Sidebar buildWorkspaceSidebar(
  BuildContext context,
  WorkspaceManager manager,
  Future<bool> Function() onRequestCloseEditor,
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
            child: Text(
              manager.project!.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
    builder: (context, scrollController) => ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: flatNodes.length,
      itemBuilder: (context, index) {
        return _buildTreeRowForNode(
          context,
          manager,
          onRequestCloseEditor,
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

        if (manager.expandedTrackId == track.id) {
          nodes.add(
            SidebarNode(
              id: '${track.id}_audio',
              type: SidebarNodeType.audio,
              collection: col,
              track: track,
              depth: 2,
            ),
          );
          nodes.add(
            SidebarNode(
              id: '${track.id}_text',
              type: SidebarNodeType.text,
              collection: col,
              track: track,
              depth: 2,
            ),
          );
        }
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

Widget _buildTreeRowForNode(
  BuildContext context,
  WorkspaceManager manager,
  Future<bool> Function() onRequestCloseEditor,
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
        onDoubleTap: () => manager.setEditingNode(col.id),
        onEditComplete: (newName) => manager.renameCollection(col, newName),
        onTap: () async {
          if (manager.editingNodeId != null) {
            manager.setEditingNode(null);
            return;
          }

          if (isColSelected) {
            manager.toggleExpandedNode(col.id);
            return;
          }

          if (manager.hasUnsavedChanges &&
              manager.selectedNode?.type == NodeType.track) {
            final proceed = await onRequestCloseEditor();
            if (!proceed) return;
          }

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

      return _buildTreeRow(
        context: context,
        label: track.name,
        icon: CupertinoIcons.waveform_path,
        iconColor: _getTrackColor(context, track.status),
        isSelected: isTrackSelected,
        isExpanded: manager.expandedTrackId == track.id,
        depth: 1,
        hasChildren: true,
        isEditing: manager.editingNodeId == track.id,
        onDoubleTap: () => manager.setEditingNode(track.id),
        onEditComplete: (newName) => manager.renameTrack(track, col, newName),
        onTap: () async {
          if (manager.editingNodeId != null) {
            manager.setEditingNode(null);
            return;
          }

          if (isTrackSelected) {
            manager.setExpandedTrack(
              manager.expandedTrackId == track.id ? null : track.id,
            );
            return;
          }

          if (manager.hasUnsavedChanges &&
              manager.selectedNode?.type == NodeType.track) {
            final proceed = await onRequestCloseEditor();
            if (!proceed) return;
          }

          manager.selectNode(
            TreeSelection(type: NodeType.track, collection: col, track: track),
          );
          manager.loadTrackInEditor(track);
        },
      );

    case SidebarNodeType.audio:
    case SidebarNodeType.text:
      final isAudio = node.type == SidebarNodeType.audio;
      final track = node.track!;
      final col = node.collection!;

      final resolved = isAudio
          ? track.getResolvedAudioPath(
              manager.project!.directoryPath,
              col.folderName,
            )
          : track.getResolvedTextPath(
              manager.project!.directoryPath,
              col.folderName,
            );

      final fileExists = resolved != null && File(resolved).existsSync();
      final isNodeSelected =
          manager.selectedNode?.track == track &&
          manager.selectedNode?.type ==
              (isAudio ? NodeType.audio : NodeType.text);

      return _buildTreeRow(
        context: context,
        label: resolved != null
            ? p.basename(resolved)
            : (isAudio ? '[⚠️ Missing Audio]' : '[⚠️ Missing Text]'),
        icon: isAudio
            ? CupertinoIcons.speaker_2_fill
            : CupertinoIcons.doc_text_fill,
        iconColor: fileExists
            ? AppTheme.grey(context)
            : AppTheme.destructive(context),
        isSelected: isNodeSelected,
        isExpanded: false,
        depth: 2,
        hasChildren: false,
        onTap: () async {
          if (manager.hasUnsavedChanges &&
              manager.selectedNode?.type == NodeType.track) {
            final proceed = await onRequestCloseEditor();
            if (!proceed) return;
          }
          manager.selectNode(
            TreeSelection(
              type: isAudio ? NodeType.audio : NodeType.text,
              collection: col,
              track: track,
            ),
          );
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
  VoidCallback? onDoubleTap,
  bool isEditing = false,
  ValueChanged<String>? onEditComplete,
}) {
  final theme = MacosTheme.of(context);
  final selectionBg = AppTheme.selectionBg(context);

  return GestureDetector(
    onTap: onTap,
    onDoubleTap: onDoubleTap,
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
            Icon(
              isExpanded
                  ? CupertinoIcons.chevron_down
                  : CupertinoIcons.chevron_right,
              size: 12,
              color: isSelected
                  ? AppTheme.selectionText(context)
                  : CupertinoColors.systemGrey,
            )
          else
            const SizedBox(width: 12),
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
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: isSelected
                          ? AppTheme.selectionText(context)
                          : theme.typography.body.color,
                    ),
                  ),
          ),
        ],
      ),
    ),
  );
}
