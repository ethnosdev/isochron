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
  final TextEditingController _ffmpegCtrl = TextEditingController(
    text: 'ffmpeg',
  );
  final TextEditingController _espeakCtrl = TextEditingController(
    text: 'espeak-ng',
  );

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
    super.dispose();
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
              // 1. Toolbar (Files & Actions)
              _buildToolbar(state),

              if (state.isProcessing)
                LinearProgressIndicator(value: state.progress),

              // 2. Waveform Editor (Only visible if we have data)
              if (state.fragments.isNotEmpty && state.waveformData != null)
                Expanded(
                  flex: 1,
                  child: Card(
                    margin: const EdgeInsets.all(8),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(
                                  state.isPlaying
                                      ? Icons.pause
                                      : Icons.play_arrow,
                                ),
                                onPressed: _controller.togglePlay,
                              ),
                              const Text("Drag teal lines to adjust timing."),
                            ],
                          ),
                          Expanded(
                            child: WaveformEditor(
                              controller: _controller,
                              state: state,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // 3. Text List
              Expanded(
                flex: 2,
                child: state.fragments.isEmpty
                    ? Center(child: Text(state.statusMessage))
                    : ListView.separated(
                        itemCount: state.fragments.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final f = state.fragments[i];
                          final isActive =
                              state.currentPlaybackPosition.inMilliseconds >=
                                  (f.realStart * 1000) &&
                              state.currentPlaybackPosition.inMilliseconds <=
                                  (f.realEnd * 1000);

                          return ListTile(
                            selected: isActive,
                            selectedTileColor: Colors.teal.withOpacity(0.1),
                            leading: Text(f.index.toString()),
                            title: Text(f.text),
                            subtitle: Text(
                              "${f.realStart.toStringAsFixed(2)}s - ${f.realEnd.toStringAsFixed(2)}s",
                            ),
                            onTap: () {
                              _controller.seekTo(
                                Duration(
                                  milliseconds: (f.realStart * 1000).toInt(),
                                ),
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

  Widget _buildToolbar(AppState state) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          ElevatedButton.icon(
            icon: const Icon(Icons.description),
            label: Text(state.textPath == null ? "Pick Text" : "Text Loaded"),
            onPressed: _controller.pickText,
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.audio_file),
            label: Text(
              state.audioPath == null ? "Pick Audio" : "Audio Loaded",
            ),
            onPressed: _controller.pickAudio,
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
