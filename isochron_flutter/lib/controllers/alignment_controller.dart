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

  /// Updates a fragment's timing and automatically synchronizes neighbors
  /// to ensure continuous alignment (no gaps, no overlaps).
  void updateFragment(int index, double newStart, double newEnd) {
    // 1. Get a shallow copy of the list (to pass as a new reference later)
    final frags = List<Fragment>.from(value.fragments);
    final duration = value.audioDuration.inMilliseconds / 1000.0;

    // 2. Validate File Bounds
    // Ensure we don't drag outside the file's duration.
    double s = newStart.clamp(0.0, duration);
    double e = newEnd.clamp(0.0, duration);

    // 3. Validate Minimum Duration (e.g. 10ms)
    // Prevents "inverting" a fragment (start > end).
    if (e <= s + 0.01) {
      // Decide which handle was moved by checking current state
      if (s != frags[index].realStart) {
        // Start was moved -> push Start back or limit it
        s = e - 0.01;
      } else {
        // End was moved -> push End forward
        e = s + 0.01;
      }
    }

    // 4. Update Current Fragment
    frags[index].setRealTiming(start: s, end: e);

    // 5. Sync Previous Fragment (Magnetic Start)
    // "Always update the end value of the previous fragment same as the start value of the current"
    if (index > 0) {
      final prev = frags[index - 1];

      // Safety: If we dragged Start back so far it swallows the previous fragment,
      // we collapse the previous fragment to its start point (0 duration effectively).
      double prevStart = prev.realStart;
      if (prevStart > s) prevStart = s;

      prev.setRealTiming(start: prevStart, end: s);
    }

    // 6. Sync Next Fragment (Magnetic End)
    // Standard contiguous logic: If we move the End, the Next Start should follow.
    if (index < frags.length - 1) {
      final next = frags[index + 1];

      // Safety: If we dragged End forward so far it swallows the next fragment.
      double nextEnd = next.realEnd;
      if (nextEnd < e) nextEnd = e;

      next.setRealTiming(start: e, end: nextEnd);
    }

    // 7. Trigger UI Update
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
