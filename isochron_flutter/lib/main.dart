import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'controllers/alignment_controller.dart';
import 'models/app_state.dart';
import 'widgets/waveform_editor.dart';

void main() {
  runApp(const IsochronApp());
}

class IsochronApp extends StatelessWidget {
  const IsochronApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Isochron Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final AlignmentController _controller = AlignmentController();

  // We keep the ScrollController here so the List can manipulate the Waveform view
  final ScrollController _waveformScrollCtrl = ScrollController();

  final TextEditingController _ffmpegCtrl = TextEditingController();
  final TextEditingController _espeakCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _ffmpegCtrl.text = prefs.getString('ffmpeg_path') ?? 'ffmpeg';
      _espeakCtrl.text = prefs.getString('espeak_path') ?? 'espeak-ng';
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _waveformScrollCtrl.dispose();
    _ffmpegCtrl.dispose();
    _espeakCtrl.dispose();
    super.dispose();
  }

  /// Jumps the audio and the waveform view to the specific fragment
  void _jumpToFragment(int index, AppState state, double viewportWidth) {
    final frag = state.fragments[index];
    final ms = (frag.realStart * 1000).toInt();

    // 1. Seek Audio
    _controller.seekTo(Duration(milliseconds: ms));

    // 2. Center Waveform View
    if (state.audioDuration.inMilliseconds > 0) {
      // Calculate total width of the waveform at current zoom
      final totalContentWidth = viewportWidth * state.zoomLevel;

      // Calculate where the start time is in pixels
      final pct = ms / state.audioDuration.inMilliseconds;
      final targetPixel = totalContentWidth * pct;

      // Calculate scroll position to center that pixel
      final centeredScrollPos = targetPixel - (viewportWidth / 2);

      if (_waveformScrollCtrl.hasClients) {
        _waveformScrollCtrl.jumpTo(
          centeredScrollPos.clamp(
            0.0,
            _waveformScrollCtrl.position.maxScrollExtent,
          ),
        );
      }
    }
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
              // 1. Top Toolbar (File Selection)
              _buildFileToolbar(state),

              if (state.isProcessing)
                LinearProgressIndicator(value: state.progress),

              // 2. Waveform Editor Area (Only visible if waveform loaded)
              if (state.fragments.isNotEmpty && state.waveform != null) ...[
                // A. Controls (Zoom & Transport)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  color: Colors.grey.shade100,
                  child: Row(
                    children: [
                      // Transport
                      IconButton(
                        icon: const Icon(Icons.skip_previous),
                        onPressed: _controller.skipToPrevious,
                        tooltip: "Previous Segment",
                      ),
                      IconButton(
                        icon: Icon(
                          state.isPlaying
                              ? Icons.pause_circle
                              : Icons.play_circle,
                          size: 40,
                          color: Colors.teal,
                        ),
                        onPressed: _controller.playPause,
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next),
                        onPressed: _controller.skipToNext,
                        tooltip: "Next Segment",
                      ),

                      const SizedBox(width: 20),
                      Container(width: 1, height: 24, color: Colors.grey),
                      const SizedBox(width: 20),

                      // Zoom Controls
                      const Icon(Icons.zoom_out, size: 18, color: Colors.grey),
                      Expanded(
                        child: Slider(
                          min: 1.0,
                          max: 10.0,
                          value: state.zoomLevel,
                          label: "${state.zoomLevel.toStringAsFixed(1)}x",
                          onChanged: (val) => _controller.setZoom(val),
                        ),
                      ),
                      const Icon(Icons.zoom_in, size: 18, color: Colors.grey),
                    ],
                  ),
                ),

                // B. The Visualizer
                Expanded(
                  flex: 1, // Takes 1/3 of available space
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.symmetric(
                        horizontal: BorderSide(color: Colors.grey.shade300),
                      ),
                      color: Colors.white,
                    ),
                    // LayoutBuilder needed to get the viewport width for scrolling logic
                    child: LayoutBuilder(
                      builder: (ctx, constraints) {
                        return WaveformEditor(
                          controller: _controller,
                          state: state,
                          scrollController: _waveformScrollCtrl,
                        );
                      },
                    ),
                  ),
                ),
              ],

              // 3. Fragment List Area
              Expanded(
                flex: 2, // Takes 2/3 of available space
                child: state.fragments.isEmpty
                    ? Center(
                        child: Text(
                          state.statusMessage,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, listConstraints) {
                          // We use viewport width from the list's context
                          // (assuming list and waveform are same width)
                          final width = listConstraints.maxWidth;

                          return ListView.separated(
                            itemCount: state.fragments.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (ctx, i) {
                              final f = state.fragments[i];

                              // Determine if this row is "active" based on playback time
                              final cPos =
                                  state.currentPlaybackPosition.inMilliseconds;
                              final isActive =
                                  cPos >= (f.realStart * 1000) &&
                                  cPos <= (f.realEnd * 1000);

                              return ListTile(
                                dense: true,
                                selected: isActive,
                                selectedTileColor: Colors.teal.withOpacity(0.1),
                                leading: CircleAvatar(
                                  radius: 14,
                                  backgroundColor: isActive
                                      ? Colors.teal
                                      : Colors.grey.shade300,
                                  foregroundColor: isActive
                                      ? Colors.white
                                      : Colors.black87,
                                  child: Text(
                                    "${f.index}",
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  f.text,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: isActive
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                                subtitle: Text(
                                  "${f.realStart.toStringAsFixed(2)}s  ➝  ${f.realEnd.toStringAsFixed(2)}s",
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                                trailing: isActive
                                    ? const Icon(
                                        Icons.volume_up,
                                        size: 16,
                                        color: Colors.teal,
                                      )
                                    : null,
                                onTap: () => _jumpToFragment(i, state, width),
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFileToolbar(AppState state) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Wrap(
        spacing: 8.0,
        runSpacing: 8.0,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // 1. Text File Picker
          OutlinedButton.icon(
            icon: const Icon(Icons.description, size: 18),
            label: const Text("Text"),
            onPressed: _controller.pickText,
            style: state.textPath != null
                ? OutlinedButton.styleFrom(
                    foregroundColor: Colors.teal,
                    side: const BorderSide(color: Colors.teal),
                  )
                : null,
          ),

          // 2. Audio File Picker
          OutlinedButton.icon(
            icon: const Icon(Icons.audio_file, size: 18),
            label: const Text("Audio"),
            onPressed: _controller.pickAudio,
            style: state.audioPath != null
                ? OutlinedButton.styleFrom(
                    foregroundColor: Colors.teal,
                    side: const BorderSide(color: Colors.teal),
                  )
                : null,
          ),

          // 3. Dictionary Picker (Optional)
          OutlinedButton.icon(
            icon: const Icon(Icons.translate, size: 18),
            label: const Text("Dict (JSON)"),
            onPressed: _controller.pickDict,
            style: state.dictPath != null
                ? OutlinedButton.styleFrom(
                    foregroundColor: Colors.deepPurple,
                    side: const BorderSide(color: Colors.deepPurple),
                  )
                : null,
          ),

          // 4. Action Button
          ElevatedButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text("Run Alignment"),
            onPressed:
                (state.textPath != null &&
                    state.audioPath != null &&
                    !state.isProcessing)
                ? () => _controller.runAlignment(
                    _ffmpegCtrl.text,
                    _espeakCtrl.text,
                  )
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
