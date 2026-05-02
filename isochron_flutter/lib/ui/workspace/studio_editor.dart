import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'; // Still needed for some base widgets like ScrollController
import 'package:isochron_flutter/ui/home_manager.dart';
import 'package:isochron_flutter/ui/models/app_state.dart';
import 'package:isochron_flutter/ui/waveform/waveform_view.dart';
import 'package:isochron_flutter/ui/workspace/studio_fragment_list.dart';
import 'package:macos_ui/macos_ui.dart';

// Note: You'll need to adapt these two imports to remove Material dependencies later
// import '../waveform/waveform_view.dart';
// import 'studio_fragment_list.dart';

class StudioEditor extends StatefulWidget {
  final HomeManager homeManager;

  const StudioEditor({super.key, required this.homeManager});

  @override
  State<StudioEditor> createState() => _StudioEditorState();
}

class _StudioEditorState extends State<StudioEditor> {
  final ScrollController _waveScroll = ScrollController();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppState>(
      valueListenable: widget.homeManager,
      builder: (context, state, _) {
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

        return Column(
          children: [
            // --- 1. Waveform Controls (Native macOS style) ---
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                  const Spacer(),
                  const MacosIcon(CupertinoIcons.zoom_out, size: 14),
                  SizedBox(
                    width: 150,
                    child: MacosSlider(
                      value: state.zoomLevel.clamp(1.0, 20.0),
                      min: 1.0,
                      max: 20.0,
                      onChanged: widget.homeManager.setZoom,
                    ),
                  ),
                  const MacosIcon(CupertinoIcons.zoom_in, size: 14),
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
                ),
              ),
            ),

            // --- 3. Fragment List ---
            Expanded(
              flex: 3,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: MacosTheme.of(context).dividerColor),
                  ),
                  color: MacosTheme.of(context).canvasColor,
                ),
                child: StudioFragmentList(
                  fragments: state.fragments,
                  currentPos: state.currentPlaybackPosition,
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
                      Duration(milliseconds: (frag.realStart * 1000).toInt()),
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
    );
  }
}
