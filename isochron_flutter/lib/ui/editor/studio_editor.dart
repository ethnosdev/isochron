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

        // Listen-and-Nudge Timings (Cmd + Arrows): 50ms
        const SingleActivator(LogicalKeyboardKey.arrowRight, meta: true): () =>
            widget.homeManager.nudgeActiveBoundary(0.050),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, meta: true): () =>
            widget.homeManager.nudgeActiveBoundary(-0.050),

        // Fine Nudge (Cmd + Opt + Arrows): 10ms
        const SingleActivator(
          LogicalKeyboardKey.arrowRight,
          meta: true,
          alt: true,
        ): () => widget.homeManager.nudgeActiveBoundary(0.010),
        const SingleActivator(
          LogicalKeyboardKey.arrowLeft,
          meta: true,
          alt: true,
        ): () => widget.homeManager.nudgeActiveBoundary(-0.010),

        // Coarse Nudge (Cmd + Shift + Arrows): 250ms
        const SingleActivator(
          LogicalKeyboardKey.arrowRight,
          meta: true,
          shift: true,
        ): () => widget.homeManager.nudgeActiveBoundary(0.250),
        const SingleActivator(
          LogicalKeyboardKey.arrowLeft,
          meta: true,
          shift: true,
        ): () => widget.homeManager.nudgeActiveBoundary(-0.250),

        // Boundary snippet playback (B)
        const SingleActivator(LogicalKeyboardKey.keyB): () =>
            widget.homeManager.playBoundarySnippet(),

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
