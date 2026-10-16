import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:isochron_flutter/ui/app_manager.dart';
import 'package:isochron_flutter/ui/models/app_state.dart';
import 'package:macos_ui/macos_ui.dart';

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

  @override
  Widget build(BuildContext context) {
    // Wrap the entire editor in a shortcut listener
    return CallbackShortcuts(
      bindings: {
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

        // Save (Cmd + S)
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
            widget.homeManager.saveProject(),

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
            // Editor State
            return Column(
              children: [
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

                // --- 3. Fragment List ---
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: MacosTheme.of(context).dividerColor,
                        ),
                      ),
                      color: MacosTheme.of(context).canvasColor,
                    ),
                    child: StudioFragmentList(
                      fragments: state.fragments,
                      playbackNotifier: widget.homeManager.playbackPosition,
                      selectedIndex: state.selectedFragmentIndex,
                      onSelect: widget.homeManager.selectFragment,
                      onCapture: (i) =>
                          widget.homeManager.captureFragmentTiming(context, i),
                      onClear: widget.homeManager.clearFragmentTiming,
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
