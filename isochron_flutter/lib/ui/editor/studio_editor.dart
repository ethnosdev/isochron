import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:isochron_flutter/ui/app_manager.dart';
import 'package:isochron_flutter/ui/models/app_state.dart';
import 'package:macos_ui/macos_ui.dart';

import '../waveform/waveform_view.dart';
import 'components/studio_fragment_list.dart';

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

    final currentSec =
        widget.homeManager.playbackPosition.value.inMilliseconds / 1000.0;

    final activeIndex = state.fragments.indexWhere(
      (f) => currentSec >= f.realStart && currentSec < f.realEnd,
    );

    if (activeIndex != -1) {
      final frag = state.fragments[activeIndex];

      // Distance to the boundary BEFORE the cursor
      final distToStart = currentSec - frag.realStart;
      // Distance to the boundary AFTER the cursor
      final distToEnd = frag.realEnd - currentSec;

      // If the playhead is sitting right on the UPCOMING timing (closer to the end,
      // and within 0.5s of it), nudge that upcoming timing instead.
      if (distToEnd < distToStart &&
          distToEnd <= 0.5 &&
          activeIndex + 1 < state.fragments.length) {
        final nextFrag = state.fragments[activeIndex + 1];
        widget.homeManager.updateFragment(
          activeIndex + 1,
          nextFrag.realStart + deltaSeconds,
          nextFrag.realEnd,
        );
        return;
      }

      // Normally, move the timing BEFORE the cursor (the start of the current fragment)
      widget.homeManager.updateFragment(
        activeIndex,
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
        _getActivePlayheadIndex() ??
        state.selectedFragmentIndex;
    if (idx != null) widget.homeManager.lockFragmentsUntil(idx);
  }

  void _handleTogglePin() {
    final state = widget.homeManager.value;
    final idx =
        widget.homeManager.hoveredFragmentIndex ??
        state.focusedFragmentIndex ??
        _getActivePlayheadIndex() ??
        state.selectedFragmentIndex;
    if (idx != null) widget.homeManager.toggleFragmentPin(idx);
  }

  int? _getActivePlayheadIndex() {
    final state = widget.homeManager.value;
    final currentSec =
        widget.homeManager.playbackPosition.value.inMilliseconds / 1000.0;
    final idx = state.fragments.indexWhere(
      (f) =>
          f.realStart >= 0 &&
          currentSec >= f.realStart &&
          currentSec < f.realEnd,
    );
    return idx != -1 ? idx : null;
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
