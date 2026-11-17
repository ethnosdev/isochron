import 'package:flutter/widgets.dart';
import 'package:isochron_flutter/ui/theme/app_icons.dart';
import 'package:isochron_flutter/services/export_service.dart';
import 'package:isochron_flutter/ui/components/macos_dialogs.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:isochron_flutter/ui/workspace/components/export_prompt_helper.dart';
import 'package:isochron_flutter/ui/workspace/models/workspace_models.dart';
import 'package:isochron_flutter/ui/workspace/workspace_manager.dart';
import 'package:isochron_cli/isochron_cli.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:isochron_flutter/ui/theme/app_theme.dart';

ToolBar buildWorkspaceToolbar(BuildContext context, WorkspaceManager manager) {
  final selectedNode = manager.selectedNode;

  Future<void> requestDeleteTrack(Track track, Collection collection) async {
    final bool? confirm = await showAppAlertDialog<bool>(
      context: context,
      builder: (dialogContext) => MacosAlertDialog(
        appIcon: const MacosIcon(
          AppIcons.trash,
          color: MacosColors.systemRedColor,
          size: 48,
        ),
        title: const Text('Delete Track?'),
        message: Text(
          'Are you sure you want to remove "${track.name}" from this collection?',
        ),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Delete'),
        ),
        secondaryButton: PushButton(
          controlSize: ControlSize.large,
          secondary: true,
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
      ),
    );

    if (confirm == true) {
      await manager.deleteTrack(track, collection);
    }
  }

  Future<void> handleExportPhraseTimingForTrack(Track track) {
    return exportSingleTrackWithPrompt(context, manager.project, track);
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
          label: 'Auto-Align',
          icon: MacosIcon(
            AppIcons.wand_rays,
            color: MacosTheme.of(context).typography.body.color,
          ),
          showLabel: true,
          onPressed: () async {
            final track = selectedNode!.track!;
            final frags = manager.homeManager.value.fragments;
            final hasUserEdits = frags.any(
              (f) =>
                  f.status == FragmentStatus.edited ||
                  f.status == FragmentStatus.reviewed,
            );
            final hasExistingAlignment = frags.any((f) => f.realStart >= 0);

            bool keepEdits = false;
            if (hasUserEdits && context.mounted) {
              final choice = await showAppSheet<int>(
                context: context,
                barrierDismissible: true,
                builder: (dialogCtx) {
                  final theme = MacosTheme.of(dialogCtx);
                  return MacosSheet(
                    child: SizedBox(
                      width: 340,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const MacosIcon(AppIcons.wand_rays, size: 42),
                            const SizedBox(height: 12),
                            Text(
                              'Re-align Track?',
                              style: theme.typography.headline.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "This track contains edited or reviewed verse boundaries.\n\n"
                              "Choose 'Keep My Edits' to lock your reviewed boundaries and only re-align automatic verses, "
                              "or 'Overwrite All' to recalculate all boundaries.\n\n"
                              "A backup (.bak) of the current alignment will be saved.",
                              style: theme.typography.body,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: PushButton(
                                controlSize: ControlSize.large,
                                onPressed: () => Navigator.pop(dialogCtx, 1),
                                child: const Text('Keep My Edits'),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: PushButton(
                                controlSize: ControlSize.large,
                                secondary: true,
                                onPressed: () => Navigator.pop(dialogCtx, 2),
                                child: const Text('Overwrite All'),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: PushButton(
                                controlSize: ControlSize.large,
                                secondary: true,
                                onPressed: () => Navigator.pop(dialogCtx, 0),
                                child: const Text('Cancel'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
              if (choice == null || choice == 0) return;
              keepEdits = (choice == 1);
            } else if (hasExistingAlignment && context.mounted) {
              final choice = await showAppAlertDialog<bool>(
                context: context,
                builder: (dialogCtx) => MacosAlertDialog(
                  appIcon: const MacosIcon(AppIcons.wand_rays, size: 48),
                  title: const Text('Re-align Track?'),
                  message: const Text(
                    'This track already has alignment data. Recalculating will overwrite the existing alignment.\n\n'
                    'A backup (.bak) of the current alignment will be saved.',
                  ),
                  primaryButton: PushButton(
                    controlSize: ControlSize.large,
                    onPressed: () => Navigator.pop(dialogCtx, true),
                    child: const Text('Overwrite'),
                  ),
                  secondaryButton: PushButton(
                    controlSize: ControlSize.large,
                    secondary: true,
                    onPressed: () => Navigator.pop(dialogCtx, false),
                    child: const Text('Cancel'),
                  ),
                ),
              );
              if (choice != true) return;
            }

            try {
              await manager.homeManager.runAlignment(
                trackId: track.id,
                keepEdits: keepEdits,
              );
            } catch (e) {
              if (context.mounted) {
                showAppAlertDialog(
                  context: context,
                  builder: (dialogCtx) => MacosAlertDialog(
                    appIcon: const MacosIcon(
                      AppIcons.exclamationmark_triangle_fill,
                      size: 48,
                    ),
                    title: const Text('Alignment Error'),
                    message: Text(e.toString()),
                    primaryButton: PushButton(
                      controlSize: ControlSize.large,
                      onPressed: () => Navigator.pop(dialogCtx),
                      child: const Text('OK'),
                    ),
                  ),
                );
              }
            }
          },
        ),
        ToolBarIconButton(
          label: 'Export Timing',
          icon: MacosIcon(
            AppIcons.square_arrow_down,
            color: ExportService.canExportPhraseTiming(selectedNode!.track!)
                ? MacosTheme.of(context).typography.body.color
                : MacosColors.systemGrayColor.withValues(alpha: 0.5),
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
            AppIcons.zoom_out,
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
            AppIcons.zoom_in,
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
          icon: MacosIcon(
            AppIcons.trash,
            color: AppTheme.destructive(context),
          ),
          showLabel: false,
          tooltipMessage: 'Delete Track',
          onPressed: () =>
              requestDeleteTrack(selectedNode.track!, selectedNode.collection!),
        ),
      ],
    ],
  );
}
