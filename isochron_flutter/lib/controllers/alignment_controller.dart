import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:isochron_cli/isochron_cli.dart';
import 'package:just_waveform/just_waveform.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_state.dart';
import 'package:path/path.dart' as p;

class AlignmentController extends ValueNotifier<AppState> {
  final AudioPlayer _player = AudioPlayer();
  static const String _keyLastDir = 'last_picked_directory';

  AlignmentController() : super(const AppState()) {
    // Listen to audio player position updates
    _player.positionStream.listen((pos) {
      value = value.copyWith(currentPlaybackPosition: pos);
    });

    _player.playerStateStream.listen((state) {
      value = value.copyWith(isPlaying: state.playing);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  // --- File Picking ---

  Future<void> pickAudio() async {
    final path = await _pickWithMemory(type: FileType.audio);

    if (path != null) {
      // Load duration for playback logic
      await _player.setFilePath(path);
      final duration = _player.duration ?? Duration.zero;

      // Reset state (clear old fragments/waveform) but keep text if loaded
      value = value.copyWith(
        audioPath: path,
        audioDuration: duration,
        statusMessage: "Audio loaded: ${p.basename(path)}",
        // Clear old results
        fragments: [],
        waveform: null,
      );

      // OPTIONAL: Pre-calculate waveform now so it appears instantly after alignment
      // We don't await this so it doesn't block the UI
      _loadWaveform(path);
    }
  }

  Future<void> pickText() async {
    final path = await _pickWithMemory(
      type: FileType.custom,
      extensions: ['txt'],
    );
    if (path != null) {
      value = value.copyWith(
        textPath: path,
        statusMessage: "Text loaded: ${p.basename(path)}",
        // We don't clear fragments here; user might want to swap text while keeping audio
      );
    }
  }

  // 4. Update pickDict
  Future<void> pickDict() async {
    final path = await _pickWithMemory(
      type: FileType.custom,
      extensions: ['json'],
    );
    if (path != null) {
      value = value.copyWith(
        dictPath: path,
        statusMessage: "Dictionary loaded: ${p.basename(path)}",
      );
    }
  }

  Future<String?> _pickWithMemory({
    required FileType type,
    List<String>? extensions,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final initialDir = prefs.getString(_keyLastDir);

    final result = await FilePicker.platform.pickFiles(
      type: type,
      allowedExtensions: extensions,
      initialDirectory: initialDir,
      lockParentWindow: true,
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      // Save the directory for next time
      final dir = File(path).parent.path;
      await prefs.setString(_keyLastDir, dir);
      return path;
    }
    return null;
  }

  // --- Processing ---

  Future<void> runAlignment(String ffmpegPath, String espeakPath) async {
    if (value.audioPath == null || value.textPath == null) return;

    value = value.copyWith(
      isProcessing: true,
      progress: 0.0,
      statusMessage: "Reading files...",
    );

    final receivePort = ReceivePort();

    // Read dictionary content if it exists
    String? rulesJsonContent;
    if (value.dictPath != null) {
      try {
        rulesJsonContent = await File(value.dictPath!).readAsString();
      } catch (e) {
        value = value.copyWith(
          statusMessage: "Error reading dictionary: $e",
          isProcessing: false,
        );
        return;
      }
    }

    try {
      await Isolate.spawn(_isolateEntry, {
        'sendPort': receivePort.sendPort,
        'textPath': value.textPath,
        'audioPath': value.audioPath,
        'rulesJson': rulesJsonContent,
        'ffmpeg': ffmpegPath,
        'espeak': espeakPath,
      });

      await for (final message in receivePort) {
        if (message['type'] == 'progress') {
          value = value.copyWith(
            statusMessage: message['status'],
            progress: message['value'],
          );
        } else if (message['type'] == 'result') {
          final List<Fragment> results = message['data'];

          await _loadWaveform(value.audioPath!);

          value = value.copyWith(
            fragments: results,
            statusMessage: "Alignment Complete",
            progress: 1.0,
            isProcessing: false,
          );
          receivePort.close();
        } else if (message['type'] == 'error') {
          throw message['error'];
        }
      }
    } catch (e) {
      value = value.copyWith(isProcessing: false, statusMessage: "Error: $e");
      receivePort.close();
    }
  }

  // --- Waveform Loading ---

  /// Reads audio file bytes and downsamples them for visualization
  Future<void> _loadWaveform(String audioPath) async {
    try {
      // 1. Get the temp directory
      final tempDir = await getTemporaryDirectory();

      // FIX: Explicitly create the directory if it doesn't exist.
      // errno = 2 often happens because this folder is missing.
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }

      // 2. Prepare paths
      final waveFileName = '${p.basename(audioPath)}.wave';
      final waveFile = File(p.join(tempDir.path, waveFileName));
      final audioFile = File(audioPath);

      // Check source existence just in case
      if (!await audioFile.exists()) {
        value = value.copyWith(statusMessage: "Source audio not found.");
        return;
      }

      // 3. Start Extraction
      JustWaveform.extract(
        audioInFile: audioFile,
        waveOutFile: waveFile,
      ).listen(
        (progressEvent) {
          if (progressEvent.waveform != null) {
            value = value.copyWith(
              waveform: progressEvent.waveform,
              statusMessage: "Waveform loaded.",
            );
          }
        },
        onError: (e) {
          // It's helpful to print this to the debug console
          debugPrint("Waveform extraction error: $e");
          value = value.copyWith(statusMessage: "Waveform error: $e");
        },
      );
    } catch (e) {
      debugPrint("Waveform setup error: $e");
      value = value.copyWith(statusMessage: "Failed to generate waveform: $e");
    }
  }

  // --- Playback Controls ---

  void playPause() {
    if (value.isPlaying)
      _player.pause();
    else
      _player.play();
  }

  void skipToNext() {
    final currentMs = value.currentPlaybackPosition.inMilliseconds;
    // Find the first fragment that starts *after* current position
    final nextFrag = value.fragments.firstWhere(
      (f) => (f.realStart * 1000) > currentMs + 100, // +100ms buffer
      orElse: () => value.fragments.last,
    );
    seekTo(Duration(milliseconds: (nextFrag.realStart * 1000).toInt()));
  }

  void skipToPrevious() {
    final currentMs = value.currentPlaybackPosition.inMilliseconds;
    // Find last fragment that started *before* current position
    final prevFrag = value.fragments.lastWhere(
      (f) => (f.realStart * 1000) < currentMs - 100,
      orElse: () => value.fragments.first,
    );
    seekTo(Duration(milliseconds: (prevFrag.realStart * 1000).toInt()));
  }

  void seekTo(Duration position) {
    _player.seek(position);
  }

  // --- Zooming ---

  void setZoom(double level) {
    // Clamp zoom between 1.0 (fit) and 20.0 (super detailed)
    final clamped = level.clamp(1.0, 20.0);
    value = value.copyWith(zoomLevel: clamped);
  }

  // --- Editor Logic ---

  /// Updates a fragment's timing and refreshes UI
  void updateFragmentTiming(int index, double newStart, double newEnd) {
    final currentList = List<Fragment>.from(value.fragments);

    // 1. Get neighbors limits
    double minAllowed = 0.0;
    double maxAllowed = value.audioDuration.inMilliseconds / 1000.0;

    if (index > 0) {
      // Cannot start before previous segment ends
      minAllowed = currentList[index - 1].realEnd;
    }

    if (index < currentList.length - 1) {
      // Cannot end after next segment starts
      maxAllowed = currentList[index + 1].realStart;
    }

    // 2. Clamp values
    // Ensure start doesn't overlap previous
    double safeStart = max(newStart, minAllowed);
    // Ensure end doesn't overlap next
    double safeEnd = min(newEnd, maxAllowed);

    // Ensure start < end (minimum duration 100ms for sanity)
    if (safeEnd - safeStart < 0.1) {
      if (_draggingStart) {
        safeStart = safeEnd - 0.1;
      } else {
        safeEnd = safeStart + 0.1;
      }
    }

    currentList[index].setRealTiming(start: safeStart, end: safeEnd);
    value = value.copyWith(fragments: currentList);
  }

  // Helper for the UI to know which handle is active to apply specific logic
  bool _draggingStart = true;
  void setDragMode(bool isStart) {
    _draggingStart = isStart;
  }

  static Future<void> _isolateEntry(Map<String, dynamic> args) async {
    final SendPort sendPort = args['sendPort'];
    final workDir = Directory.systemTemp.createTempSync('iso_bg_');

    // Parse Rules
    Map<String, String>? rules;
    if (args['rulesJson'] != null) {
      final rawMap = jsonDecode(args['rulesJson']) as Map<String, dynamic>;
      rules = rawMap.map((key, value) => MapEntry(key, value.toString()));
    }

    try {
      final text = await File(args['textPath']).readAsString();

      final frags = await IsochronProcessor.process(
        text: text,
        audioPath: args['audioPath'],
        workDir: workDir,
        ffmpegPath: args['ffmpeg'],
        espeakPath: args['espeak'],
        transliterationRules: rules, // Pass rules here
        onProgress: (s, p) =>
            sendPort.send({'type': 'progress', 'status': s, 'value': p}),
      );

      sendPort.send({'type': 'result', 'data': frags});
    } catch (e) {
      sendPort.send({'type': 'error', 'error': e.toString()});
    } finally {
      workDir.deleteSync(recursive: true);
    }
  }
}
