import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:isochron_cli/isochron_cli.dart';
import '../models/app_state.dart';

class AlignmentController extends ValueNotifier<AppState> {
  final AudioPlayer _player = AudioPlayer();

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
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (result != null) {
      final path = result.files.single.path!;

      // Load audio into player to get duration
      await _player.setFilePath(path);
      final duration = _player.duration ?? Duration.zero;

      value = value.copyWith(
        audioPath: path,
        audioDuration: duration,
        statusMessage: "Audio loaded.",
        waveformData: null, // Clear old waveform until processed
      );
    }
  }

  Future<void> pickText() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt'],
    );
    if (result != null) {
      value = value.copyWith(
        textPath: result.files.single.path,
        statusMessage: "Text loaded.",
      );
    }
  }

  // --- Processing ---

  Future<void> runAlignment(String ffmpegPath, String espeakPath) async {
    if (value.audioPath == null || value.textPath == null) return;

    value = value.copyWith(
      isProcessing: true,
      progress: 0.0,
      statusMessage: "Starting engine...",
    );

    final receivePort = ReceivePort();

    try {
      await Isolate.spawn(_isolateEntry, {
        'sendPort': receivePort.sendPort,
        'textPath': value.textPath,
        'audioPath': value.audioPath,
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

          // After alignment, let's load the waveform data for visualization
          // We use the normalized 16k mono file created by the CLI in the temp dir
          // NOTE: In a real app, pass the path back. Here we assume we reload user audio.
          await _loadWaveform(value.audioPath!);

          value = value.copyWith(
            fragments: results,
            statusMessage: "Done!",
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
  Future<void> _loadWaveform(String path) async {
    // For simplicity, we read the whole file.
    // In production, use a library or FFI to read large files in chunks.
    final file = File(path);
    final bytes = await file.readAsBytes();

    // Rudimentary WAV parsing (Skipping header, assuming 16-bit)
    // Real implementation should parse header to find data chunk
    const headerSize = 44;
    if (bytes.length <= headerSize) return;

    final int16Data = bytes.buffer.asInt16List(headerSize);

    // Decimate to ~2000 points (enough for screen width) or more if zooming
    const targetPoints = 4000;
    final step = (int16Data.length / targetPoints).ceil();
    final data = Float64List(targetPoints);

    for (int i = 0; i < targetPoints; i++) {
      final index = i * step;
      if (index < int16Data.length) {
        // Normalize 16-bit int to -1.0 -> 1.0
        data[i] = int16Data[index] / 32768.0;
      }
    }

    value = value.copyWith(waveformData: data);
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
    // ... (Copy existing Isolate logic from your previous main.dart here) ...
    // ... Ensure you import IsochronProcessor ...
    final SendPort sendPort = args['sendPort'];
    final workDir = Directory.systemTemp.createTempSync('iso_bg_');

    try {
      final text = await File(args['textPath']).readAsString();
      final frags = await IsochronProcessor.process(
        text: text,
        audioPath: args['audioPath'],
        workDir: workDir,
        ffmpegPath: args['ffmpeg'],
        espeakPath: args['espeak'],
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
