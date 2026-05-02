import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:isochron_flutter/ui/app_manager.dart';
import 'package:isochron_flutter/ui/models/app_state.dart';
import 'package:macos_ui/macos_ui.dart';

import '../waveform/waveform_view.dart';
import 'studio_fragment_list.dart';

class StudioEditor extends StatefulWidget {
  final AppManager homeManager;

  const StudioEditor({super.key, required this.homeManager});

  @override
  State<StudioEditor> createState() => _StudioEditorState();
}

class _StudioEditorState extends State<StudioEditor> {
  final ScrollController _waveScroll = ScrollController();

  // --- Keyboard Action Handlers ---

  void _handleNudge(double deltaSeconds) {
    final state = widget.homeManager.value;
    if (state.fragments.isEmpty) return;

    final currentMs = widget.homeManager.playbackPosition.value.inMilliseconds;
    final index = state.fragments.indexWhere(
      (f) =>
          currentMs >= (f.realStart * 1000) && currentMs <= (f.realEnd * 1000),
    );

    if (index != -1) {
      final frag = state.fragments[index];
      widget.homeManager.updateFragment(
        index,
        frag.realStart + deltaSeconds,
        frag.realEnd,
      );
    }
  }

  void _handleLockUntil() {
    final state = widget.homeManager.value;
    final idx =
        widget.homeManager.hoveredFragmentIndex ??
        state.focusedFragmentIndex ??
        state.selectedFragmentIndex;
    if (idx != null) widget.homeManager.lockFragmentsUntil(idx);
  }

  void _handleTogglePin() {
    final state = widget.homeManager.value;
    final idx =
        widget.homeManager.hoveredFragmentIndex ??
        state.focusedFragmentIndex ??
        state.selectedFragmentIndex;
    if (idx != null) widget.homeManager.toggleFragmentPin(idx);
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

        // Nudge Timings (Cmd + Arrows)
        const SingleActivator(LogicalKeyboardKey.arrowRight, meta: true): () =>
            _handleNudge(0.15),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, meta: true): () =>
            _handleNudge(-0.15),

        // Pinning (L / Shift + L)
        const SingleActivator(LogicalKeyboardKey.keyL): _handleLockUntil,
        const SingleActivator(LogicalKeyboardKey.keyL, shift: true):
            _handleTogglePin,

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
            // Loading State
            if (state.isProcessing) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const ProgressCircle(),
                    const SizedBox(height: 16),
                    Text(
                      state.statusMessage,
                      style: MacosTheme.of(context).typography.headline,
                    ),
                  ],
                ),
              );
            }

            // Editor State
            return Column(
              children: [
                // --- 1. Waveform Controls ---
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
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
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      MacosIconButton(
                        icon: const MacosIcon(CupertinoIcons.backward_end),
                        onPressed: widget.homeManager.skipToPrevious,
                      ),
                      const SizedBox(width: 8),
                      MacosIconButton(
                        icon: MacosIcon(
                          state.isPlaying
                              ? CupertinoIcons.pause_solid
                              : CupertinoIcons.play_arrow_solid,
                        ),
                        onPressed: widget.homeManager.togglePlay,
                        backgroundColor: MacosTheme.of(context).primaryColor,
                      ),
                      const SizedBox(width: 8),
                      MacosIconButton(
                        icon: const MacosIcon(CupertinoIcons.forward_end),
                        onPressed: widget.homeManager.skipToNext,
                      ),
                      // const Spacer(),
                      // const MacosIcon(CupertinoIcons.zoom_out, size: 14),
                      // SizedBox(
                      //   width: 150,
                      //   child: MacosSlider(
                      //     value: state.zoomLevel.clamp(1.0, 20.0),
                      //     min: 1.0,
                      //     max: 20.0,
                      //     onChanged: widget.homeManager.setZoom,
                      //   ),
                      // ),
                      // const MacosIcon(CupertinoIcons.zoom_in, size: 14),
                    ],
                  ),
                ),

                // --- 2. Waveform View ---
                Expanded(
                  flex: 2,
                  child: Container(
                    width: double.infinity,
                    color: MacosTheme.of(context).canvasColor,
                    child: WaveformView(
                      controller: widget.homeManager,
                      state: state,
                      scrollController: _waveScroll,
                      playbackNotifier: widget.homeManager.playbackPosition,
                    ),
                  ),
                ),

                // --- 3. Fragment List ---
                Expanded(
                  flex: 3,
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
                      rules: state.transliterationRules,
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
                            milliseconds: (frag.realStart * 1000).toInt(),
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
