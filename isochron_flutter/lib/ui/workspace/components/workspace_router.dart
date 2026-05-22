import 'package:flutter/cupertino.dart';
import 'package:file_picker/file_picker.dart';
import 'package:isochron_flutter/ui/editor/studio_editor.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:isochron_flutter/ui/workspace/models/workspace_models.dart';
import 'package:isochron_flutter/ui/workspace/views/audio_inspector_view.dart';
import 'package:isochron_flutter/ui/workspace/views/collection_batch_view.dart';
import 'package:isochron_flutter/ui/workspace/views/project_settings_view.dart';
import 'package:isochron_flutter/ui/workspace/views/text_editor_view.dart';
import 'package:isochron_flutter/ui/workspace/workspace_manager.dart';
import 'package:macos_ui/macos_ui.dart';

class WorkspaceRouter extends StatelessWidget {
  final WorkspaceManager manager;

  const WorkspaceRouter({super.key, required this.manager});

  Future<void> _invalidateAndReplace(
    BuildContext context,
    Track track,
    Future<void> Function() action,
  ) async {
    if (track.status != AlignmentStatus.pending) {
      final bool? confirm = await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Invalidate Alignment?'),
          content: const Text(
            'Modifying this file will invalidate your existing alignment data. Are you sure?',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Modify'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    await action();
    await manager.clearAlignmentData(track);
  }

  Future<void> _handleHealBrokenLinks(
    BuildContext context,
    Collection collection,
  ) async {
    final String? selectedFolder = await FilePicker.getDirectoryPath(
      dialogTitle: 'Select Root Folder of Missing Media',
    );
    if (selectedFolder == null) return;

    final healedCount = await manager.healBrokenLinks(
      collection,
      selectedFolder,
    );

    if (context.mounted) {
      if (healedCount > 0) {
        showMacosAlertDialog(
          context: context,
          builder: (context) => MacosAlertDialog(
            appIcon: const MacosIcon(CupertinoIcons.checkmark_seal_fill),
            title: const Text('Broken Links Healed'),
            message: Text(
              'Successfully located and updated $healedCount missing files.',
              textAlign: TextAlign.center,
            ),
            primaryButton: PushButton(
              controlSize: ControlSize.large,
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ),
        );
      } else {
        showMacosAlertDialog(
          context: context,
          builder: (context) => MacosAlertDialog(
            appIcon: const MacosIcon(
              CupertinoIcons.exclamationmark_triangle_fill,
            ),
            title: const Text('No Matches Found'),
            message: const Text(
              'Scanned the directory but could not find any files matching the missing filenames.',
              textAlign: TextAlign.center,
            ),
            primaryButton: PushButton(
              controlSize: ControlSize.large,
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (manager.selectedNode == null) {
      return const Center(child: Text("Select a collection or track."));
    }

    switch (manager.selectedNode!.type) {
      case NodeType.collection:
        return CollectionBatchView(
          collection: manager.selectedNode!.collection!,
          project: manager.project!,
          isRunning: manager.isBatchRunning,
          status: manager.batchStatus,
          progress: manager.batchProgress,
          onRunBatch: () => manager.runBatch(manager.selectedNode!.collection!),
          onStopBatch: manager.stopBatch,
          onChanged: () {
            manager.project!.save();
            manager.refreshUi();
          },
          onOpenTrack: (track) {
            manager.selectNode(
              TreeSelection(
                type: NodeType.track,
                collection: manager.selectedNode!.collection,
                track: track,
              ),
            );
            manager.loadTrackInEditor(track);
          },
          onHealBrokenLinks: () => _handleHealBrokenLinks(
            context,
            manager.selectedNode!.collection!,
          ),
        );

      case NodeType.track:
        return StudioEditor(homeManager: manager.homeManager);

      case NodeType.text:
        return TextEditorView(
          track: manager.selectedNode!.track!,
          project: manager.project!,
          collection: manager.selectedNode!.collection!,
          onReplaceOrEdit: (action) => _invalidateAndReplace(
            context,
            manager.selectedNode!.track!,
            action,
          ),
        );

      case NodeType.audio:
        return AudioInspectorView(
          track: manager.selectedNode!.track!,
          project: manager.project!,
          collection: manager.selectedNode!.collection!,
          onReplace: (action) => _invalidateAndReplace(
            context,
            manager.selectedNode!.track!,
            action,
          ),
        );

      case NodeType.settings:
        return ProjectSettingsView(
          project: manager.project!,
          onSaved: () {
            manager.project!.save();
            manager.refreshUi();
          },
        );
    }
  }
}
