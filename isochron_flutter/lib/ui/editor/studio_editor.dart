import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:isochron_cli/isochron_cli.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'package:isochron_flutter/ui/app_manager.dart';
import 'package:isochron_flutter/ui/models/app_state.dart';
import 'package:isochron_flutter/ui/theme/app_theme.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path/path.dart' as p;

import '../waveform/waveform_view.dart';
import 'components/studio_fragment_list.dart';

class StudioEditor extends StatefulWidget {
  final AppManager homeManager;

  const StudioEditor({
    super.key,
    required this.homeManager,
  });

  @override
  State<StudioEditor> createState() => _StudioEditorState();
}

class _StudioEditorState extends State<StudioEditor> {
  final ScrollController _waveScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _waveScroll.dispose();
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyUpEvent) {
      final keys = HardwareKeyboard.instance.logicalKeysPressed;
      final hasModifier = keys.contains(LogicalKeyboardKey.meta) ||
          keys.contains(LogicalKeyboardKey.metaLeft) ||
          keys.contains(LogicalKeyboardKey.metaRight) ||
          keys.contains(LogicalKeyboardKey.control) ||
          keys.contains(LogicalKeyboardKey.controlLeft) ||
          keys.contains(LogicalKeyboardKey.controlRight);
      if (!hasModifier) {
        widget.homeManager.clearNudgeLatch();
      }
    }
    return false;
  }

  void _scrollToTime(
    double anchorTime,
    double zoomLevel,
    Duration audioDuration,
  ) {
    if (audioDuration.inMilliseconds == 0) return;

    void doScroll() {
      if (!_waveScroll.hasClients) return;

      final viewportWidth = _waveScroll.position.viewportDimension;
      final totalDuration = audioDuration.inMilliseconds / 1000.0;
      final centerOffset = WaveformView.calculateCenterOffset(
        anchorTime: anchorTime,
        totalDurationSeconds: totalDuration,
        viewportWidth: viewportWidth,
        zoomLevel: zoomLevel,
      );

      _waveScroll.animateTo(
        centerOffset.clamp(
          0.0,
          _waveScroll.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }

    if (_waveScroll.hasClients) {
      doScroll();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => doScroll());
    }
  }

  String _formatTimecode(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hundredths =
        (d.inMilliseconds.remainder(1000) ~/ 10).toString().padLeft(2, '0');
    return "$minutes:$seconds.$hundredths";
  }

  Widget _buildFilterPill({
    required BuildContext context,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = MacosTheme.of(context);
    final accent = AppTheme.accent(context);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
        decoration: BoxDecoration(
          color: isSelected
              ? accent.withValues(alpha: 0.18)
              : theme.canvasColor.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? accent.withValues(alpha: 0.4)
                : theme.dividerColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? accent : theme.typography.body.color,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);

    // Wrap the entire editor in a shortcut listener
    return CallbackShortcuts(
      bindings: {
        // Undo / Redo
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () =>
            widget.homeManager.undo(),
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          meta: true,
          shift: true,
        ): () => widget.homeManager.redo(),
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
            widget.homeManager.undo(),
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): () => widget.homeManager.redo(),

        // Play / Pause (Space)
        const SingleActivator(LogicalKeyboardKey.space): () =>
            widget.homeManager.togglePlay(),

        // Skip Next/Prev (Arrows)
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            widget.homeManager.skipToNext(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            widget.homeManager.skipToPrevious(),

        // Standard Nudge (Cmd / Ctrl + Arrows): 150ms
        const SingleActivator(LogicalKeyboardKey.arrowRight, meta: true): () =>
            widget.homeManager.nudgeActiveBoundary(0.150),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, meta: true): () =>
            widget.homeManager.nudgeActiveBoundary(-0.150),
        const SingleActivator(LogicalKeyboardKey.arrowRight, control: true): () =>
            widget.homeManager.nudgeActiveBoundary(0.150),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true): () =>
            widget.homeManager.nudgeActiveBoundary(-0.150),

        // Fine Nudge (Cmd / Ctrl + Opt + Arrows): 50ms
        const SingleActivator(
          LogicalKeyboardKey.arrowRight,
          meta: true,
          alt: true,
        ): () => widget.homeManager.nudgeActiveBoundary(0.050),
        const SingleActivator(
          LogicalKeyboardKey.arrowLeft,
          meta: true,
          alt: true,
        ): () => widget.homeManager.nudgeActiveBoundary(-0.050),
        const SingleActivator(
          LogicalKeyboardKey.arrowRight,
          control: true,
          alt: true,
        ): () => widget.homeManager.nudgeActiveBoundary(0.050),
        const SingleActivator(
          LogicalKeyboardKey.arrowLeft,
          control: true,
          alt: true,
        ): () => widget.homeManager.nudgeActiveBoundary(-0.050),

        // Coarse Nudge (Cmd / Ctrl + Shift + Arrows): 500ms
        const SingleActivator(
          LogicalKeyboardKey.arrowRight,
          meta: true,
          shift: true,
        ): () => widget.homeManager.nudgeActiveBoundary(0.500),
        const SingleActivator(
          LogicalKeyboardKey.arrowLeft,
          meta: true,
          shift: true,
        ): () => widget.homeManager.nudgeActiveBoundary(-0.500),
        const SingleActivator(
          LogicalKeyboardKey.arrowRight,
          control: true,
          shift: true,
        ): () => widget.homeManager.nudgeActiveBoundary(0.500),
        const SingleActivator(
          LogicalKeyboardKey.arrowLeft,
          control: true,
          shift: true,
        ): () => widget.homeManager.nudgeActiveBoundary(-0.500),

        // Play current fragment and stop (P)
        const SingleActivator(LogicalKeyboardKey.keyP): () =>
            widget.homeManager.playCurrentFragment(),

        // Mark Reviewed & Advance (R)
        const SingleActivator(LogicalKeyboardKey.keyR): () =>
            widget.homeManager.markReviewedAndAdvance(),

        // Jump to next verse with diagnostic flags (F)
        const SingleActivator(LogicalKeyboardKey.keyF): () =>
            widget.homeManager.jumpToNextFlaggedVerse(),

        // Capture Timing (Enter)
        const SingleActivator(LogicalKeyboardKey.enter): () =>
            widget.homeManager.captureFragmentTiming(context),

        // Control + Up/Down to Zoom
        const SingleActivator(LogicalKeyboardKey.arrowUp, control: true): () =>
            widget.homeManager.setZoom(
              widget.homeManager.value.zoomLevel * 1.5,
            ),
        const SingleActivator(
          LogicalKeyboardKey.arrowDown,
          control: true,
        ): () => widget.homeManager.setZoom(
          widget.homeManager.value.zoomLevel / 1.5,
        ),
      },
      child: Focus(
        autofocus:
            true, // Auto-focus this widget so it catches keystrokes immediately
        child: ValueListenableBuilder<AppState>(
          valueListenable: widget.homeManager,
          builder: (context, state, _) {
            final allCount = state.fragments.length;
            final unreviewedCount = state.fragments
                .where((f) => f.status != FragmentStatus.reviewed)
                .length;
            final flaggedCount = state.fragments
                .where((f) => f.flags.isNotEmpty || f.warnings.isNotEmpty)
                .length;

            return Column(
              children: [
                // --- Missing File Fallback Banner ---
                if (state.audioPath == null || state.textPath == null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color:
                          AppTheme.destructive(context).withValues(alpha: 0.12),
                      border: Border(
                        bottom: BorderSide(
                          color: AppTheme.destructive(context).withValues(
                            alpha: 0.3,
                          ),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          CupertinoIcons.exclamationmark_triangle_fill,
                          size: 16,
                          color: AppTheme.destructive(context),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            state.audioPath == null && state.textPath == null
                                ? "Audio and transcript files are missing for this track."
                                : state.audioPath == null
                                    ? "Audio file is missing for this track."
                                    : "Transcript file is missing for this track.",
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (state.audioPath == null) ...[
                          PushButton(
                            controlSize: ControlSize.small,
                            onPressed: () async {
                              final settings = UserSettingsService();
                              final picked = await FilePicker.pickFiles(
                                type: FileType.audio,
                                initialDirectory: settings.lastSourceDir,
                              );
                              if (picked != null &&
                                  picked.files.single.path != null) {
                                final pth = picked.files.single.path!;
                                settings.setLastSourceDir(p.dirname(pth));
                                await widget.homeManager
                                    .replaceCurrentTrackAudio(pth);
                              }
                            },
                            child: const Text("Attach Audio..."),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (state.textPath == null)
                          PushButton(
                            controlSize: ControlSize.small,
                            onPressed: () async {
                              final settings = UserSettingsService();
                              final picked = await FilePicker.pickFiles(
                                type: FileType.custom,
                                allowedExtensions: ['txt', 'phrases'],
                                initialDirectory: settings.lastSourceDir,
                              );
                              if (picked != null &&
                                  picked.files.single.path != null) {
                                final pth = picked.files.single.path!;
                                settings.setLastSourceDir(p.dirname(pth));
                                await widget.homeManager
                                    .replaceCurrentTrackText(pth);
                              }
                            },
                            child: const Text("Attach Transcript..."),
                          ),
                      ],
                    ),
                  ),

                // --- Processing Bar ---
                if (state.isProcessing)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: MacosTheme.of(context).canvasColor,
                      border: Border(
                        bottom: BorderSide(
                          color: MacosTheme.of(context).dividerColor,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 200,
                          child: Text(
                            state.statusMessage,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ProgressBar(value: state.progress * 100),
                        ),
                      ],
                    ),
                  ),

                // --- 2. Waveform View ---
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  width: double.infinity,
                  color: MacosTheme.of(context).canvasColor,
                  child: WaveformView(
                    controller: widget.homeManager,
                    state: state,
                    scrollController: _waveScroll,
                    playbackNotifier: widget.homeManager.playbackPosition,
                  ),
                ),

                // --- 3. Transport & Triage Control Bar (Height 42px) ---
                Container(
                  height: 42.0,
                  padding: const EdgeInsets.symmetric(horizontal: 14.0),
                  decoration: BoxDecoration(
                    color: AppTheme.selectionBg(context).withValues(alpha: 0.35),
                    border: Border(
                      top: BorderSide(color: theme.dividerColor),
                      bottom: BorderSide(color: theme.dividerColor),
                    ),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: math.max(0.0, constraints.maxWidth - 28.0),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Left Group (Transport & Timecode)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  MacosTooltip(
                                    message: "Play / Pause (Space)",
                                    child: MacosIconButton(
                                      icon: MacosIcon(
                                        state.isPlaying
                                            ? CupertinoIcons.pause_fill
                                            : CupertinoIcons.play_arrow_solid,
                                        color: AppTheme.accent(context),
                                        size: 16,
                                      ),
                                      onPressed: widget.homeManager.togglePlay,
                                      boxConstraints: const BoxConstraints(
                                        minHeight: 28,
                                        minWidth: 28,
                                      ),
                                    ),
                                  ),
                                  MacosTooltip(
                                    message: "Play Current Fragment (P)",
                                    child: MacosIconButton(
                                      icon: MacosIcon(
                                        CupertinoIcons.repeat_1,
                                        color: theme.typography.body.color,
                                        size: 16,
                                      ),
                                      onPressed: widget.homeManager.playCurrentFragment,
                                      boxConstraints: const BoxConstraints(
                                        minHeight: 28,
                                        minWidth: 28,
                                      ),
                                    ),
                                  ),
                                  MacosTooltip(
                                    message: "Previous (←)",
                                    child: MacosIconButton(
                                      icon: MacosIcon(
                                        CupertinoIcons.backward_end_fill,
                                        color: theme.typography.body.color,
                                        size: 14,
                                      ),
                                      onPressed: widget.homeManager.skipToPrevious,
                                      boxConstraints: const BoxConstraints(
                                        minHeight: 28,
                                        minWidth: 28,
                                      ),
                                    ),
                                  ),
                                  MacosTooltip(
                                    message: "Next (→)",
                                    child: MacosIconButton(
                                      icon: MacosIcon(
                                        CupertinoIcons.forward_end_fill,
                                        color: theme.typography.body.color,
                                        size: 14,
                                      ),
                                      onPressed: widget.homeManager.skipToNext,
                                      boxConstraints: const BoxConstraints(
                                        minHeight: 28,
                                        minWidth: 28,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ValueListenableBuilder<Duration>(
                                    valueListenable:
                                        widget.homeManager.playbackPosition,
                                    builder: (context, pos, _) {
                                      return Text(
                                        "${_formatTimecode(pos)} / ${_formatTimecode(state.audioDuration)}",
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.grey(context),
                                          fontWeight: FontWeight.w500,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),

                              const SizedBox(width: 16),

                              // Center Group (Filter Pills & Flag Navigation)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildFilterPill(
                                    context: context,
                                    label: "All ($allCount)",
                                    isSelected: state.filter == FragmentFilter.all,
                                    onTap: () => widget.homeManager
                                        .setFilter(FragmentFilter.all),
                                  ),
                                  const SizedBox(width: 6),
                                  _buildFilterPill(
                                    context: context,
                                    label: "Unreviewed ($unreviewedCount)",
                                    isSelected:
                                        state.filter == FragmentFilter.unreviewed,
                                    onTap: () => widget.homeManager
                                        .setFilter(FragmentFilter.unreviewed),
                                  ),
                                  const SizedBox(width: 6),
                                  _buildFilterPill(
                                    context: context,
                                    label: "Flagged ($flaggedCount)",
                                    isSelected:
                                        state.filter == FragmentFilter.flagged,
                                    onTap: () => widget.homeManager
                                        .setFilter(FragmentFilter.flagged),
                                  ),
                                  if (flaggedCount > 0) ...[
                                    const SizedBox(width: 8),
                                    PushButton(
                                      controlSize: ControlSize.small,
                                      secondary: true,
                                      onPressed:
                                          widget.homeManager.jumpToNextFlaggedVerse,
                                      child: const Text("⚠️ Next Flag (F)"),
                                    ),
                                  ],
                                ],
                              ),

                              const SizedBox(width: 16),

                              // Right Group (Review & Undo/Redo)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  PushButton(
                                    controlSize: ControlSize.small,
                                    secondary: true,
                                    onPressed:
                                        widget.homeManager.markReviewedAndAdvance,
                                    child: const Text("✓ Mark Reviewed (R)"),
                                  ),
                                  const SizedBox(width: 8),
                                  MacosTooltip(
                                    message: "Undo (⌘Z)",
                                    child: MacosIconButton(
                                      icon: MacosIcon(
                                        CupertinoIcons.arrow_turn_up_left,
                                        color: widget.homeManager.canUndo
                                            ? theme.typography.body.color
                                            : AppTheme.grey(context).withValues(
                                                alpha: 0.4,
                                              ),
                                        size: 15,
                                      ),
                                      boxConstraints: const BoxConstraints(
                                        minHeight: 28,
                                        minWidth: 28,
                                      ),
                                      onPressed: widget.homeManager.canUndo
                                          ? widget.homeManager.undo
                                          : null,
                                    ),
                                  ),
                                  MacosTooltip(
                                    message: "Redo (⇧⌘Z)",
                                    child: MacosIconButton(
                                      icon: MacosIcon(
                                        CupertinoIcons.arrow_turn_up_right,
                                        color: widget.homeManager.canRedo
                                            ? theme.typography.body.color
                                            : AppTheme.grey(context).withValues(
                                                alpha: 0.4,
                                              ),
                                        size: 15,
                                      ),
                                      boxConstraints: const BoxConstraints(
                                        minHeight: 28,
                                        minWidth: 28,
                                      ),
                                      onPressed: widget.homeManager.canRedo
                                          ? widget.homeManager.redo
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // --- 4. Fragment List ---
                Expanded(
                  child: Container(
                    color: MacosTheme.of(context).canvasColor,
                    child: StudioFragmentList(
                      fragments: state.fragments,
                      playbackNotifier: widget.homeManager.playbackPosition,
                      selectedIndex: state.selectedFragmentIndex,
                      filter: state.filter,
                      onSelect: widget.homeManager.selectFragment,
                      onCapture: (i) =>
                          widget.homeManager.captureFragmentTiming(context, i),
                      onClear: widget.homeManager.clearFragmentTiming,
                      onToggleReviewed:
                          widget.homeManager.toggleFragmentReviewed,
                      onEditText: (i, newText) =>
                          widget.homeManager.updateFragmentText(i, newText),
                      onJumpTo: (idx) {
                        widget.homeManager.exitFocusMode();
                        final frag = state.fragments[idx];
                        widget.homeManager.seekTo(
                          Duration(
                            milliseconds: (frag.realStart * 1000).ceil(),
                          ),
                        );
                        if (frag.realStart >= 0) {
                          _scrollToTime(
                            frag.realStart,
                            widget.homeManager.value.zoomLevel,
                            widget.homeManager.value.audioDuration,
                          );
                        }
                      },
                      onDoubleTap: (idx) {
                        widget.homeManager.enterFocusMode(idx);
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
