import 'package:flutter/material.dart';
import 'package:isochron_flutter/ui/widgets/waveform/fragment_list.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../controllers/alignment_controller.dart';
import '../../models/app_state.dart';
import '../widgets/control_bar.dart';
import '../widgets/waveform/waveform_view.dart';
import '../widgets/waveform/waveform_controls.dart'; // Assume this exists (simple row of buttons)

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final AlignmentController _controller = AlignmentController();
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
                  onSkipNext: _controller.skipToNext,
                  onSkipPrev: _controller.skipToPrevious,
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
                  onJumpTo: (idx) => _jumpTo(idx, state),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _jumpTo(int index, AppState state) {
    final frag = state.fragments[index];
    final ms = (frag.realStart * 1000).toInt();
    _controller.seekTo(Duration(milliseconds: ms));

    // Sync Scroll Logic
    if (state.audioDuration.inMilliseconds > 0 && _waveScroll.hasClients) {
      final totalWidth =
          _waveScroll.position.viewportDimension * state.zoomLevel;
      final targetPx = (ms / state.audioDuration.inMilliseconds) * totalWidth;
      final centerOffset =
          targetPx - (_waveScroll.position.viewportDimension / 2);
      _waveScroll.jumpTo(
        centerOffset.clamp(0.0, _waveScroll.position.maxScrollExtent),
      );
    }
  }
}
