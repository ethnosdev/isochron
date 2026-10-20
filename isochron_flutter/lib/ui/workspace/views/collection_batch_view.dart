import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:isochron_flutter/ui/components/macos_dialogs.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:isochron_flutter/ui/theme/app_theme.dart';
import 'package:isochron_flutter/ui/workspace/components/group_export_dialog.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path/path.dart' as p;

class CollectionBatchView extends StatefulWidget {
  final Collection collection;
  final Project project;
  final bool isRunning;
  final String status;
  final double progress;
  final VoidCallback onRunBatch;
  final VoidCallback onStopBatch;
  final VoidCallback onChanged;
  final VoidCallback onImportFiles;
  final VoidCallback? onClearTracks;
  final void Function(Track track) onOpenTrack;
  final VoidCallback onHealBrokenLinks;
  final ValueChanged<String>? onRenameCollection;

  const CollectionBatchView({
    super.key,
    required this.collection,
    required this.project,
    required this.isRunning,
    required this.status,
    required this.progress,
    required this.onRunBatch,
    required this.onStopBatch,
    required this.onChanged,
    required this.onImportFiles,
    this.onClearTracks,
    required this.onOpenTrack,
    required this.onHealBrokenLinks,
    this.onRenameCollection,
  });

  @override
  State<CollectionBatchView> createState() => _CollectionBatchViewState();
}

class _CollectionBatchViewState extends State<CollectionBatchView> {
  void _promptRenameCollection() {
    final controller = TextEditingController(text: widget.collection.name);
    showAppAlertDialog(
      context: context,
      builder: (ctx) => MacosAlertDialog(
        appIcon: const MacosIcon(CupertinoIcons.pencil_circle),
        title: const Text('Rename Collection'),
        message: Column(
          children: [
            const Text('Enter a new name for this collection:'),
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
        widget.onRenameCollection?.call(newName.trim());
      }
    });
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = MacosTheme.of(context);

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        margin: const EdgeInsets.all(32.0),
        padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 48.0),
        decoration: BoxDecoration(
          color: theme.canvasColor,
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(
            color: theme.dividerColor,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MacosIcon(
              CupertinoIcons.tray_arrow_down,
              size: 56,
              color: AppTheme.accent(context),
            ),
            const SizedBox(height: 20),
            Text(
              "Import Audio & Transcript Files",
              style: theme.typography.title2.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              "Select or drop audio (.mp3, .wav, .m4a) and transcript (.txt) files. Files will be naturally sorted and paired automatically.",
              style: TextStyle(
                color: AppTheme.grey(context),
                fontSize: 13,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            PushButton(
              controlSize: ControlSize.large,
              onPressed: widget.onImportFiles,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MacosIcon(CupertinoIcons.plus_circle, size: 16),
                  SizedBox(width: 8),
                  Text("Add & Pair Tracks..."),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTriageDashboard(BuildContext context) {
    final theme = MacosTheme.of(context);
    final tracks = widget.collection.tracks;

    final totalTracks = tracks.length;
    final reviewedCount =
        tracks.where((t) => t.status == AlignmentStatus.reviewed).length;
    final doneCount =
        tracks.where((t) => t.status == AlignmentStatus.done).length;
    final errorCount =
        tracks.where((t) => t.status == AlignmentStatus.error).length;
    final pendingCount =
        tracks.where((t) => t.status == AlignmentStatus.pending).length;
    final processingCount =
        tracks.where((t) => t.status == AlignmentStatus.processing).length;

    // Detect broken files
    final List<Track> brokenTracks = tracks.where((t) {
      if (t.audioPath != null) {
        final p = t.getResolvedAudioPath(
          widget.project.directoryPath,
          widget.collection.folderName,
        );
        if (p == null || !File(p).existsSync()) return true;
      }
      if (t.textPath != null) {
        final p = t.getResolvedTextPath(
          widget.project.directoryPath,
          widget.collection.folderName,
        );
        if (p == null || !File(p).existsSync()) return true;
      }
      return false;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Broken links warning banner
        if (brokenTracks.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: AppTheme.destructive(context).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(
                color: AppTheme.destructive(context).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.exclamationmark_triangle_fill,
                  color: AppTheme.destructive(context),
                  size: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${brokenTracks.length} tracks in this collection have missing source files. This happens if the media directory was renamed or moved.',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 12),
                PushButton(
                  controlSize: ControlSize.regular,
                  onPressed: widget.onHealBrokenLinks,
                  child: const Text('Locate Missing Media...'),
                ),
              ],
            ),
          ),

        // Summary Header Bar & Action Row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          decoration: BoxDecoration(
            color: theme.canvasColor,
            border: Border(
              bottom: BorderSide(color: theme.dividerColor),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            widget.collection.name,
                            style: theme.typography.title1.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          MacosTooltip(
                            message: "Rename Collection",
                            child: MacosIconButton(
                              icon: MacosIcon(
                                CupertinoIcons.pencil,
                                size: 16,
                                color: AppTheme.grey(context),
                              ),
                              boxConstraints: const BoxConstraints(
                                minHeight: 24,
                                minWidth: 24,
                              ),
                              onPressed: _promptRenameCollection,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "$totalTracks tracks • $reviewedCount reviewed, $doneCount done, $pendingCount pending${errorCount > 0 ? ', $errorCount errors' : ''}",
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.grey(context),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  PushButton(
                    controlSize: ControlSize.large,
                    secondary: widget.isRunning,
                    onPressed: widget.isRunning
                        ? widget.onStopBatch
                        : widget.onRunBatch,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MacosIcon(
                          widget.isRunning
                              ? CupertinoIcons.stop_fill
                              : CupertinoIcons.play_arrow_solid,
                          size: 14,
                          color: widget.isRunning
                              ? AppTheme.destructive(context)
                              : CupertinoColors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.isRunning
                              ? "Stop Batch"
                              : "Run Alignment on All",
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  PushButton(
                    controlSize: ControlSize.large,
                    secondary: true,
                    onPressed: widget.onImportFiles,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MacosIcon(CupertinoIcons.slider_horizontal_3, size: 14),
                        SizedBox(width: 6),
                        Text("Manage Track Pairings..."),
                      ],
                    ),
                  ),
                  if (widget.onClearTracks != null) ...[
                    const SizedBox(width: 12),
                    PushButton(
                      controlSize: ControlSize.large,
                      secondary: true,
                      onPressed: widget.onClearTracks,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MacosIcon(CupertinoIcons.trash, size: 14),
                          SizedBox(width: 6),
                          Text("Clear All Tracks..."),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(width: 12),
                  PushButton(
                    controlSize: ControlSize.large,
                    secondary: true,
                    onPressed: () => GroupExportDialog.show(
                      context,
                      project: widget.project,
                      collection: widget.collection,
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MacosIcon(CupertinoIcons.square_arrow_down, size: 14),
                        SizedBox(width: 6),
                        Text("Export Timings..."),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Segmented visual progress bar
              if (totalTracks > 0)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4.0),
                  child: Container(
                    height: 8.0,
                    color: AppTheme.grey(context).withValues(alpha: 0.2),
                    child: Row(
                      children: [
                        if (reviewedCount > 0)
                          Expanded(
                            flex: reviewedCount,
                            child: Container(color: AppTheme.success(context)),
                          ),
                        if (doneCount > 0)
                          Expanded(
                            flex: doneCount,
                            child: Container(color: AppTheme.accent(context)),
                          ),
                        if (processingCount > 0)
                          Expanded(
                            flex: processingCount,
                            child: Container(color: AppTheme.warning(context)),
                          ),
                        if (errorCount > 0)
                          Expanded(
                            flex: errorCount,
                            child:
                                Container(color: AppTheme.destructive(context)),
                          ),
                        if (pendingCount > 0)
                          Expanded(
                            flex: pendingCount,
                            child: Container(
                              color:
                                  AppTheme.grey(context).withValues(alpha: 0.35),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

              if (widget.isRunning) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      widget.status,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ProgressBar(value: widget.progress * 100),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        // Richer Track Rows
        Expanded(
          child: ListView.builder(
            itemCount: tracks.length,
            itemBuilder: (ctx, i) {
              final track = tracks[i];

              final resolvedAudio = track.getResolvedAudioPath(
                widget.project.directoryPath,
                widget.collection.folderName,
              );
              final resolvedText = track.getResolvedTextPath(
                widget.project.directoryPath,
                widget.collection.folderName,
              );

              final bool audioMissing =
                  resolvedAudio == null || !File(resolvedAudio).existsSync();
              final bool textMissing =
                  resolvedText == null || !File(resolvedText).existsSync();

              // Status Icon
              Widget statusIcon;
              if (track.status == AlignmentStatus.processing) {
                statusIcon = const ProgressCircle();
              } else if (track.status == AlignmentStatus.reviewed) {
                statusIcon = Icon(
                  CupertinoIcons.checkmark_seal_fill,
                  size: 18,
                  color: AppTheme.success(context),
                );
              } else if (track.status == AlignmentStatus.done) {
                statusIcon = Icon(
                  CupertinoIcons.checkmark_circle,
                  size: 18,
                  color: AppTheme.accent(context),
                );
              } else if (track.status == AlignmentStatus.error) {
                statusIcon = Icon(
                  CupertinoIcons.exclamationmark_circle,
                  size: 18,
                  color: AppTheme.destructive(context),
                );
              } else {
                statusIcon = Icon(
                  CupertinoIcons.clock,
                  size: 18,
                  color: AppTheme.warning(context),
                );
              }

              // Status Badge Pill Color
              Color badgeColor;
              switch (track.status) {
                case AlignmentStatus.reviewed:
                case AlignmentStatus.done:
                  badgeColor = AppTheme.success(context);
                  break;
                case AlignmentStatus.processing:
                  badgeColor = AppTheme.accent(context);
                  break;
                case AlignmentStatus.error:
                  badgeColor = AppTheme.destructive(context);
                  break;
                case AlignmentStatus.pending:
                  badgeColor = AppTheme.warning(context);
                  break;
              }

              return Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: theme.dividerColor),
                  ),
                ),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => widget.onOpenTrack(track),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20.0,
                        vertical: 10.0,
                      ),
                      child: Row(
                        children: [
                          statusIcon,
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13.5,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                if (audioMissing || textMissing)
                                  Text(
                                    audioMissing && textMissing
                                        ? "Missing audio and transcript files"
                                        : audioMissing
                                            ? "Missing audio file"
                                            : "Missing transcript file",
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: AppTheme.destructive(context),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  )
                                else
                                  Text(
                                    "${p.basename(resolvedAudio)}  •  ${p.basename(resolvedText)}",
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: AppTheme.grey(context),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: badgeColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              track.status.name.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: badgeColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          MacosIconButton(
                            icon: MacosIcon(
                              CupertinoIcons.chevron_right,
                              size: 14,
                              color: AppTheme.grey(context),
                            ),
                            onPressed: () => widget.onOpenTrack(track),
                            boxConstraints: const BoxConstraints(
                              minHeight: 28,
                              minWidth: 28,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.collection.tracks.isEmpty) {
      return _buildEmptyState(context);
    }
    return _buildTriageDashboard(context);
  }
}
