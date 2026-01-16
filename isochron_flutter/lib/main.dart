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
      title: 'Isochron',
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
  // We keep the ScrollController here to manipulate it from List/Buttons
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
    super.dispose();
  }

  /// Handles clicking a list item
  void _jumpToFragment(int index, AppState state, double viewportWidth) {
    final frag = state.fragments[index];
    final ms = (frag.realStart * 1000).toInt();

    // 1. Seek Audio
    _controller.seekTo(Duration(milliseconds: ms));

    // 2. Center Waveform View
    if (state.audioDuration.inMilliseconds > 0) {
      final totalWidth = viewportWidth * state.zoomLevel;
      final pct = ms / state.audioDuration.inMilliseconds;
      final targetX = totalWidth * pct;
      final centeredX = targetX - (viewportWidth / 2);

      if (_waveformScrollCtrl.hasClients) {
        _waveformScrollCtrl.jumpTo(
          centeredX.clamp(0.0, _waveformScrollCtrl.position.maxScrollExtent),
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
              // Toolbar
              _buildFileToolbar(state),
              if (state.isProcessing)
                LinearProgressIndicator(value: state.progress),

              // EDITOR AREA
              if (state.fragments.isNotEmpty && state.waveformData != null) ...[
                // Controls Bar (Zoom + Transport)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  color: Colors.grey[100],
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
                      // Zoom
                      const Icon(Icons.zoom_out, size: 20),
                      Expanded(
                        child: Slider(
                          min: 1.0,
                          max: 10.0,
                          value: state.zoomLevel,
                          label: "${state.zoomLevel.toStringAsFixed(1)}x",
                          onChanged: (val) => _controller.setZoom(val),
                        ),
                      ),
                      const Icon(Icons.zoom_in, size: 20),
                    ],
                  ),
                ),

                // The Waveform Widget
                Expanded(
                  flex: 1, // 1/3 of remaining space
                  child: LayoutBuilder(
                    builder: (ctx, constraints) {
                      return Container(
                        decoration: BoxDecoration(
                          border: Border.symmetric(
                            horizontal: BorderSide(color: Colors.grey[300]!),
                          ),
                          color: Colors.white,
                        ),
                        child: WaveformEditor(
                          controller: _controller,
                          state: state,
                          scrollController: _waveformScrollCtrl,
                        ),
                      );
                    },
                  ),
                ),
              ],

              // LIST AREA
              Expanded(
                flex: 2, // 2/3 of remaining space
                child: state.fragments.isEmpty
                    ? Center(child: Text(state.statusMessage))
                    : LayoutBuilder(
                        builder: (context, listConstraints) {
                          return ListView.separated(
                            itemCount: state.fragments.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (ctx, i) {
                              final f = state.fragments[i];
                              // Check if active based on timestamp
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
                                  radius: 12,
                                  backgroundColor: isActive
                                      ? Colors.teal
                                      : Colors.grey[300],
                                  child: Text(
                                    "${f.index}",
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  f.text,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  "${f.realStart.toStringAsFixed(2)} - ${f.realEnd.toStringAsFixed(2)}",
                                ),
                                trailing: isActive
                                    ? const Icon(Icons.volume_up, size: 16)
                                    : null,
                                onTap: () {
                                  // The width of the waveform viewer is needed to center it
                                  // We can estimate or use a GlobalKey.
                                  // For now, we assume standard window width logic or just pass a fixed safe value.
                                  // Better: Use LayoutBuilder above List to get width? No, we need Waveform width.
                                  // Simplification: Just assume screen width or context size.
                                  _jumpToFragment(
                                    i,
                                    state,
                                    MediaQuery.of(context).size.width,
                                  );
                                },
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
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.description),
            label: const Text("Text"),
            onPressed: _controller.pickText,
            style: state.textPath != null
                ? OutlinedButton.styleFrom(foregroundColor: Colors.teal)
                : null,
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.audio_file),
            label: const Text("Audio"),
            onPressed: _controller.pickAudio,
            style: state.audioPath != null
                ? OutlinedButton.styleFrom(foregroundColor: Colors.teal)
                : null,
          ),
          const Spacer(),
          ElevatedButton(
            onPressed:
                (state.textPath != null &&
                    state.audioPath != null &&
                    !state.isProcessing)
                ? () => _controller.runAlignment(
                    _ffmpegCtrl.text,
                    _espeakCtrl.text,
                  )
                : null,
            child: const Text("Run Alignment"),
          ),
        ],
      ),
    );
  }
}
