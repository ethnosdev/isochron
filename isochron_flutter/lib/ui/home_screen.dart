import 'package:flutter/material.dart';
import 'package:isochron_flutter/ui/home/waveform/fragment_list.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_manager.dart';
import 'app_state.dart';
import 'control_bar/control_bar.dart';
import 'waveform/waveform_view.dart';
import 'waveform/waveform_controls.dart'; // Assume this exists (simple row of buttons)

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final HomeManager _controller = HomeManager();
  final ScrollController _waveScroll = ScrollController();
  final TextEditingController _ffmpegCtrl = TextEditingController();
  final TextEditingController _espeakCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _ffmpegCtrl.text = prefs.getString('ffmpeg') ?? 'ffmpeg';
    _espeakCtrl.text = prefs.getString('espeak') ?? 'espeak-ng';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Isochron Studio')),
      body: ValueListenableBuilder<AppState>(
        valueListenable: _controller,
        builder: (context, state, _) {
          return Column(
            children: [
              ControlBar(
                controller: _controller,
                state: state,
                onRun: () => _controller.runAlignment(
                  _ffmpegCtrl.text,
                  _espeakCtrl.text,
                ),
              ),

              if (state.isProcessing)
                LinearProgressIndicator(value: state.progress),

              if (state.waveform != null) ...[
                WaveformControls(
                  isPlaying: state.isPlaying,
                  zoom: state.zoomLevel,
                  onPlayPause: _controller.togglePlay,
                  onSkipNext: () => _handleSkipNext(state),
                  onSkipPrev: () => _handleSkipPrev(state),
                  onZoom: (z) => _controller.setZoom(z.toDouble()),
                ),
                Expanded(
                  flex: 1,
                  child: Container(
                    color: Colors.white,
                    child: WaveformView(
                      controller: _controller,
                      state: state,
                      scrollController: _waveScroll,
                    ),
                  ),
                ),
              ],

              Expanded(
                flex: 2,
                child: FragmentList(
                  fragments: state.fragments,
                  currentPos: state.currentPlaybackPosition,
                  // Use _jumpTo directly here
                  onJumpTo: (idx) {
                    _controller.exitFocusMode();
                    _jumpTo(idx, state);
                  },
                  onDoubleTap: (idx) {
                    _controller.enterFocusMode(idx);
                    // Also scroll to it immediately using _jumpTo logic logic (optional,
                    // but enterFocusMode usually handles center, _jumpTo handles scroll)
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _handleSkipNext(AppState state) {
    if (state.fragments.isEmpty) return;

    final currentMs = state.currentPlaybackPosition.inMilliseconds;
    // Find the first fragment that starts *after* current position (+ buffer)
    final nextIndex = state.fragments.indexWhere(
      (f) => (f.realStart * 1000) > currentMs + 100,
    );

    if (nextIndex != -1) {
      _controller.exitFocusMode(); // Optional: Exit focus mode on skip
      _jumpTo(nextIndex, state);
    }
  }

  void _handleSkipPrev(AppState state) {
    if (state.fragments.isEmpty) return;

    final currentMs = state.currentPlaybackPosition.inMilliseconds;
    // Find last fragment that started *before* current position (- buffer)
    final prevIndex = state.fragments.lastIndexWhere(
      (f) => (f.realStart * 1000) < currentMs - 100,
    );

    if (prevIndex != -1) {
      _controller.exitFocusMode(); // Optional: Exit focus mode on skip
      _jumpTo(prevIndex, state);
    } else {
      // If none found (at start), jump to 0
      _jumpTo(0, state);
    }
  }

  // --- EXISTING _jumpTo LOGIC (Updated for robust centering) ---

  void _jumpTo(int index, AppState state) {
    final frag = state.fragments[index];
    final ms = (frag.realStart * 1000).toInt();

    // 1. Seek Audio
    _controller.seekTo(Duration(milliseconds: ms));

    // 2. Center Waveform View
    if (state.audioDuration.inMilliseconds > 0 && _waveScroll.hasClients) {
      final viewportWidth = _waveScroll.position.viewportDimension;

      // Total width of the waveform at current zoom
      // Note: We use the *current* viewport width to calculate content width
      final totalContentWidth = viewportWidth * state.zoomLevel;

      final totalMs = state.audioDuration.inMilliseconds;
      final pct = ms / totalMs;

      // The pixel X coordinate of the fragment start
      final targetPixel = totalContentWidth * pct;

      // Center it: Target - (Half Viewport)
      final centeredScrollPos = targetPixel - (viewportWidth / 2);

      _waveScroll.jumpTo(
        centeredScrollPos.clamp(0.0, _waveScroll.position.maxScrollExtent),
      );
    }
  }
}
