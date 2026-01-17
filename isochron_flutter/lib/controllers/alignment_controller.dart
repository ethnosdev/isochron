import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:isochron_cli/isochron_cli.dart';
import 'package:just_waveform/just_waveform.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_state.dart';
import '../services/alignment_service.dart';
import '../services/audio_service.dart';

class AlignmentController extends ValueNotifier<AppState> {
  final AudioService _audioService = AudioService();
  final AlignmentService _alignmentService = AlignmentService();

  static const String _keyLastDir = 'last_picked_directory';

  AlignmentController() : super(const AppState()) {
    _audioService.positionStream.listen((pos) {
      value = value.copyWith(currentPlaybackPosition: pos);
    });
    _audioService.stateStream.listen((s) {
      value = value.copyWith(isPlaying: s.playing);
    });
  }

  @override
  void dispose() {
    _audioService.dispose();
    super.dispose();
  }

  // --- Actions ---

  Future<void> pickAudio() async {
    final path = await _pickFile(type: FileType.audio);
    if (path == null) return;

    final duration = await _audioService.load(path);

    value = value.copyWith(
      audioPath: path,
      audioDuration: duration,
      statusMessage: "Audio loaded: ${p.basename(path)}",
      fragments: [],
      waveform: null,
    );

    _generateWaveform(path);
  }

  Future<void> pickText() async {
    final path = await _pickFile(type: FileType.custom, extensions: ['txt']);
    if (path != null) {
      value = value.copyWith(
        textPath: path,
        statusMessage: "Text: ${p.basename(path)}",
      );
    }
  }

  Future<void> pickDict() async {
    final path = await _pickFile(type: FileType.custom, extensions: ['json']);
    if (path != null) {
      value = value.copyWith(
        dictPath: path,
        statusMessage: "Dict: ${p.basename(path)}",
      );
    }
  }

  Future<void> runAlignment(String ffmpeg, String espeak) async {
    if (value.audioPath == null || value.textPath == null) return;

    value = value.copyWith(
      isProcessing: true,
      progress: 0.0,
      statusMessage: "Starting...",
    );

    try {
      final fragments = await _alignmentService.runIsochron(
        textPath: value.textPath!,
        audioPath: value.audioPath!,
        dictPath: value.dictPath,
        ffmpegPath: ffmpeg,
        espeakPath: espeak,
        onProgress: (status, prog) {
          value = value.copyWith(statusMessage: status, progress: prog);
        },
      );

      // Refresh waveform in case it wasn't ready
      if (value.waveform == null) await _generateWaveform(value.audioPath!);

      value = value.copyWith(
        fragments: fragments,
        statusMessage: "Done.",
        progress: 1.0,
        isProcessing: false,
      );
    } catch (e) {
      value = value.copyWith(isProcessing: false, statusMessage: "Error: $e");
    }
  }

  void skipToNext() {
    if (value.fragments.isEmpty) return;

    final currentMs = value.currentPlaybackPosition.inMilliseconds;
    // Find the first fragment that starts *after* current position + small buffer
    final nextFrag = value.fragments.firstWhere(
      (f) => (f.realStart * 1000) > currentMs + 100,
      orElse: () => value.fragments.last,
    );

    // Only seek if we actually found a different spot
    if ((nextFrag.realStart * 1000) > currentMs + 100) {
      seekTo(Duration(milliseconds: (nextFrag.realStart * 1000).toInt()));
    }
  }

  void skipToPrevious() {
    if (value.fragments.isEmpty) return;

    final currentMs = value.currentPlaybackPosition.inMilliseconds;
    // Find last fragment that started *before* current position - small buffer
    final prevFrag = value.fragments.lastWhere(
      (f) => (f.realStart * 1000) < currentMs - 100,
      orElse: () => value.fragments.first,
    );

    seekTo(Duration(milliseconds: (prevFrag.realStart * 1000).toInt()));
  }

  void enterFocusMode(int index) {
    if (value.audioDuration.inMilliseconds == 0) return;

    final totalSeconds = value.audioDuration.inMilliseconds / 1000.0;

    // Calculate Zoom: We want exactly 2.0 seconds visible on screen.
    // Logic: zoomLevel = TotalDuration / DesiredVisibleDuration
    // We cap it at 500x to prevent memory/performance issues on extremely long files.
    final targetZoom = (totalSeconds / 2.0).clamp(1.0, 500.0);

    final startSeconds = value.fragments[index].realStart;
    seekTo(Duration(milliseconds: (startSeconds * 1000).toInt()));

    value = value.copyWith(zoomLevel: targetZoom, focusedFragmentIndex: index);
  }

  void exitFocusMode() {
    // Reset focus. Optionally reset zoom to 1.0 if you prefer.
    value = value.copyWith(
      clearFocus: true,
      // zoomLevel: 1.0, // Uncomment if you want to zoom out automatically
    );
  }

  /// Specialized method: Updates start time and immediately plays from there.
  void setFragmentStartAndPlay(int index, double newStartTime) {
    final frag = value.fragments[index];

    // Safety check: Start cannot be after End
    if (newStartTime >= frag.realEnd) return;

    // 1. Update the data
    updateFragment(index, newStartTime, frag.realEnd);

    // 2. Seek to new start
    seekTo(Duration(milliseconds: (newStartTime * 1000).toInt()));

    // 3. Ensure playing
    if (!value.isPlaying) {
      _audioService.play();
    }
  }

  // --- Waveform Logic ---

  Future<void> _generateWaveform(String audioPath) async {
    try {
      final tempDir = await getTemporaryDirectory();
      if (!await tempDir.exists()) await tempDir.create(recursive: true);

      final waveFile = File(
        p.join(tempDir.path, '${p.basename(audioPath)}.wave'),
      );

      JustWaveform.extract(
        audioInFile: File(audioPath),
        waveOutFile: waveFile,
      ).listen((event) {
        if (event.waveform != null) {
          value = value.copyWith(waveform: event.waveform);
        }
      });
    } catch (e) {
      debugPrint("Waveform error: $e");
    }
  }

  // --- Playback & Transport ---

  void togglePlay() =>
      value.isPlaying ? _audioService.pause() : _audioService.play();
  void seekTo(Duration d) => _audioService.seek(d);

  void setZoom(double z) {
    value = value.copyWith(zoomLevel: z.clamp(1.0, 500.0));
  }

  void updateFragment(int index, double start, double end) {
    // Basic validation logic
    final frags = List<Fragment>.from(value.fragments);
    frags[index].setRealTiming(start: start, end: end);
    value = value.copyWith(fragments: frags);
  }

  // --- Helper ---

  Future<String?> _pickFile({
    required FileType type,
    List<String>? extensions,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final initialDir = prefs.getString(_keyLastDir);
    final result = await FilePicker.platform.pickFiles(
      type: type,
      allowedExtensions: extensions,
      initialDirectory: initialDir,
    );

    if (result?.files.single.path != null) {
      final path = result!.files.single.path!;
      await prefs.setString(_keyLastDir, File(path).parent.path);
      return path;
    }
    return null;
  }
}
