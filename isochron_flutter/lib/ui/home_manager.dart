import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:isochron_cli/isochron_cli.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'package:isochron_flutter/ui/dialogs/text_preview_dialog.dart';
import 'package:isochron_flutter/ui/dialogs/transliteration_preview_dialog.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:just_waveform/just_waveform.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'models/app_state.dart';
import '../services/alignment_service.dart';
import '../services/audio_service.dart';
import '../services/pins_service.dart';

class HomeManager extends ValueNotifier<AppState> {
  final AudioService _audioService = AudioService();
  final AlignmentService _alignmentService = AlignmentService();
  final PinsService _pinsService = PinsService();
  final _settings = UserSettingsService();
  VoidCallback? onSaveCallback;

  /// Snapshot of pin state as of the last explicit save (or file load).
  /// Used by discardChanges() to revert both in-memory and on-disk pins
  /// without losing pins that were already saved.
  /// Null means no pins were saved.
  Map<int, ({double start, double end})>? _lastSavedPins;

  /// Builds a snapshot map from the pinned fragments in [frags].
  static Map<int, ({double start, double end})> _buildPinsSnapshot(
    List<Fragment> frags,
  ) => {
    for (final f in frags.where((f) => f.isPinned))
      f.index: (start: f.pinnedStart!, end: f.pinnedEnd!),
  };

  static const String _keyLastDir = 'last_picked_directory';

  HomeManager() : super(AppState(zoomLevel: UserSettingsService().lastZoom)) {
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

  Future<void> loadProjectItem(
    ProjectItem item,
    String projectRoot, {
    String? dictPath,
  }) async {
    // Reset pin snapshot for the new file — prevents stale state from a
    // previous file carrying over if this file has no alignment JSON yet.
    _lastSavedPins = null;

    // 1. Pause audio if it was playing from previous file
    if (value.isPlaying) {
      await _audioService.pause();
    }

    final absJsonPath = item.getAbsoluteOutputPath(projectRoot);

    final prefs = await SharedPreferences.getInstance();
    final ffmpegPath = prefs.getString('ffmpeg') ?? 'ffmpeg';
    final playbackPath = await _ensureWavForPlayback(
      item.audioPath,
      ffmpegPath,
    );

    // 2. Load Audio Duration
    final duration = await _audioService.load(playbackPath);

    // 3. Load Existing JSON if available
    List<Fragment> loadedFragments = [];
    if (await File(absJsonPath).exists()) {
      final content = await File(absJsonPath).readAsString();
      final List<dynamic> jsonList = jsonDecode(content);
      loadedFragments = jsonList
          .map(
            (j) =>
                Fragment(index: j['index'], id: j['id'], text: j['text'])
                  ..setRealTiming(
                    start: (j['start'] as num).toDouble(),
                    end: (j['end'] as num).toDouble(),
                  ),
          )
          .toList();

      // Restore any previously saved pin locks from sidecar file
      await _pinsService.load(absJsonPath, loadedFragments);

      // Snapshot what was actually persisted so discard can revert here
      _lastSavedPins = _buildPinsSnapshot(loadedFragments);
    }

    // 3.5. Load Dictionary if not already loaded into memory
    final actualDictPath = dictPath ?? value.dictPath;
    Map<String, String>? rules = value.transliterationRules;

    if (actualDictPath != null &&
        rules == null &&
        await File(actualDictPath).exists()) {
      try {
        final jsonString = await File(actualDictPath).readAsString();
        final Map<String, dynamic> rawMap = jsonDecode(jsonString);
        rules = rawMap.map((k, v) => MapEntry(k, v.toString()));
      } catch (e) {
        debugPrint("Failed to load dict: $e");
      }
    }

    // 4. Reset State Completely for the new file
    value = value.copyWith(
      audioPath: item.audioPath,
      textPath: item.textPath,
      dictPath: actualDictPath,
      transliterationRules: rules,
      autoSavePath: absJsonPath,
      fragments: loadedFragments,
      audioDuration: duration,
      statusMessage: "Loaded ${p.basename(item.audioPath)}",
      hasUnsavedChanges: false,
      clearWaveform: true, // Clears the old waveform
      clearFocus: true, // Clears focus
      currentPlaybackPosition: Duration.zero,
    );

    // 5. Initialize Waveform (Background)
    _generateWaveform(item.audioPath);
  }

  /// Saves to the project file immediately without a dialog
  Future<void> saveProject() async {
    if (value.autoSavePath == null) {
      // Fallback to export if not in project mode
      return exportJson();
    }

    if (value.fragments.isEmpty) return;

    try {
      value = value.copyWith(statusMessage: "Saving...");

      final List<Map<String, dynamic>> jsonList = value.fragments
          .map(
            (f) => {
              'index': f.index,
              if (f.id != null) 'id': f.id,
              'text': f.text,
              'start': double.parse(f.realStart.toStringAsFixed(3)),
              'end': double.parse(f.realEnd.toStringAsFixed(3)),
            },
          )
          .toList();

      final jsonString = const JsonEncoder.withIndent('  ').convert(jsonList);
      await File(value.autoSavePath!).writeAsString(jsonString);

      // Persist pins and update snapshot so discard now targets this save
      await savePinsFile();
      _lastSavedPins = _buildPinsSnapshot(value.fragments);

      value = value.copyWith(statusMessage: "Saved.", hasUnsavedChanges: false);
      onSaveCallback?.call();
    } catch (e) {
      value = value.copyWith(statusMessage: "Save Failed: $e");
    }
  }

  Future<void> discardChanges() async {
    // Revert in-memory fragment pins to the last-saved snapshot
    final frags = List<Fragment>.from(value.fragments);
    final snapshot = _lastSavedPins ?? {};

    for (final f in frags) {
      final saved = snapshot[f.index];
      if (saved != null) {
        f.setPinnedTiming(start: saved.start, end: saved.end);
      } else {
        f.clearPinnedTiming();
      }
    }

    // Rewrite (or delete) the sidecar to match the reverted state
    if (value.autoSavePath != null) {
      await _pinsService.save(value.autoSavePath!, frags);
    }

    value = value.copyWith(fragments: frags, hasUnsavedChanges: false);
  }

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

  Future<void> pickText(BuildContext context) async {
    final path = await _pickFile(type: FileType.custom, extensions: ['txt']);
    if (path != null) {
      // Read first few lines and ask user
      final file = File(path);
      final lines = await file.readAsLines();
      final preview = lines.take(5).toList();

      final bool? hasIds = await showDialog<bool>(
        context: context,
        builder: (_) => TextPreviewDialog(
          filename: p.basename(path),
          previewLines: preview,
        ),
      );

      if (hasIds == null) return; // User canceled

      // Store the path AND the formatting choice in AppState
      // You'll need to add `final bool hasIds;` to your AppState class first!
      value = value.copyWith(
        textPath: path,
        hasIds: hasIds,
        statusMessage: "Text: ${p.basename(path)}",
      );
    }
  }

  Future<void> pickDict(BuildContext context) async {
    final path = await _pickFile(type: FileType.custom, extensions: ['json']);
    if (path == null) return;

    // 1. Load Rules immediately
    Map<String, String>? rules;
    try {
      final jsonString = await File(path).readAsString();
      final Map<String, dynamic> rawMap = jsonDecode(jsonString);
      rules = rawMap.map((k, v) => MapEntry(k, v.toString()));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
      return;
    }

    if (value.textPath == null) {
      value = value.copyWith(
        dictPath: path,
        transliterationRules: rules,
        statusMessage: "Dict: ${p.basename(path)}",
      );
      return;
    }

    try {
      final textFile = File(value.textPath!);
      final fullText = await textFile.readAsString();

      // 2. Run Analysis in Background (compute)
      final analysis = await compute(
        _analyzeTransliteration,
        _AnalysisRequest(fullText, rules, value.hasIds),
      );

      // 3. Show Dialog
      if (!context.mounted) return;
      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (_) => TransliterationPreviewDialog(
          dictName: p.basename(path),
          previewLines: analysis.previewLines,
          unknownChars: analysis.unknownChars,
        ),
      );

      if (confirm == true) {
        value = value.copyWith(
          dictPath: path,
          transliterationRules: rules,
          statusMessage: "Dict: ${p.basename(path)}",
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  Future<void> runAlignment(
    BuildContext context,
    String ffmpeg,
    String espeak,
  ) async {
    if (value.audioPath == null || value.textPath == null) return;

    value = value.copyWith(
      isProcessing: true,
      progress: 0.0,
      statusMessage: "Starting...",
    );

    File? tempCleanTextFile;
    List<String> extractedIds = [];

    try {
      String actualTextPath = value.textPath!;

      // --- PRE-PROCESSING ---
      if (value.hasIds) {
        // Assuming you added this to AppState
        value = value.copyWith(statusMessage: "Preprocessing text...");

        final lines = await File(value.textPath!).readAsLines();
        final cleanLines = <String>[];

        for (var line in lines) {
          if (line.trim().isEmpty) continue;

          // Split by first space
          final parts = line.trim().split(' ');
          if (parts.length > 1) {
            extractedIds.add(parts.first); // Store ID
            cleanLines.add(parts.sublist(1).join(' ')); // Join rest as text
          } else {
            // Fallback if no space found
            extractedIds.add("");
            cleanLines.add(line);
          }
        }

        // Create temp file
        final tempDir = await getTemporaryDirectory();
        tempCleanTextFile = File(p.join(tempDir.path, 'clean_transcript.txt'));
        await tempCleanTextFile.writeAsString(cleanLines.join('\n'));

        actualTextPath = tempCleanTextFile.path;
      }
      // -----------------------

      // Run existing service with potentially new path
      final activePinsPath = _pinsPath;
      final passPins =
          activePinsPath != null && await File(activePinsPath).exists();

      List<Fragment> fragments = await _alignmentService.runIsochron(
        textPath: actualTextPath,
        audioPath: value.audioPath!,
        dictPath: value.dictPath,
        ffmpegPath: ffmpeg,
        espeakPath: espeak,
        pinsPath: passPins ? activePinsPath : null,
        onProgress: (status, prog) {
          value = value.copyWith(statusMessage: status, progress: prog);
        },
      );

      // --- POST-PROCESSING ---
      if (value.hasIds && extractedIds.isNotEmpty) {
        // Merge IDs back into fragments.
        // We assume 1-to-1 mapping (Line = Fragment).
        final mergedFragments = <Fragment>[];

        for (int i = 0; i < fragments.length; i++) {
          String? id;
          if (i < extractedIds.length) {
            id = extractedIds[i];
          }

          mergedFragments.add(fragments[i].copyWith(id: id));
        }
        fragments = mergedFragments;
      }

      if (value.waveform == null) await _generateWaveform(value.audioPath!);

      value = value.copyWith(
        fragments: fragments,
        statusMessage: "Done.",
        progress: 1.0,
        isProcessing: false,
      );
    } catch (e) {
      value = value.copyWith(isProcessing: false, statusMessage: "Error: $e");
      // show error dialog
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Alignment Error"),
            content: Text(e.toString()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("OK"),
              ),
            ],
          ),
        );
      }
    } finally {
      if (tempCleanTextFile != null && await tempCleanTextFile.exists()) {
        await tempCleanTextFile.delete();
      }
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

    // Calculate Zoom: We want exactly 10.0 seconds visible on screen.
    // Logic: zoomLevel = TotalDuration / DesiredVisibleDuration
    // We cap it at 500x to prevent memory/performance issues on extremely long files.
    final targetZoom = (totalSeconds / 10.0).clamp(1.0, 500.0);

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

  /// Index of the fragment the mouse is currently hovering over in the
  /// waveform view. Updated by WaveformView on every mouse-move; used by the
  /// `L` keyboard shortcut so it doesn't require a prior double-click.
  int? hoveredFragmentIndex;

  void setHoveredFragmentIndex(int? idx) {
    hoveredFragmentIndex = idx;
  }

  /// Path to the sidecar pins file: same directory as [autoSavePath] but with
  /// a `-pins.json` suffix. Returns null when not in project mode.
  String? get _pinsPath => value.autoSavePath == null
      ? null
      : PinsService.pinsPath(value.autoSavePath!);

  /// Saves pinned fragments to the sidecar via [PinsService].
  Future<void> savePinsFile() async {
    final path = _pinsPath;
    if (path == null) return;
    await _pinsService.save(value.autoSavePath!, value.fragments);
  }

  /// Toggles the pin lock on a fragment.
  /// When pinned, the fragment's current realStart/realEnd are locked in as
  /// ground-truth boundaries — drag handles are disabled and the alignment
  /// pipeline treats them as hard constraints on re-run.
  void toggleFragmentPin(int index) async {
    final frags = List<Fragment>.from(value.fragments);
    if (index < 0 || index >= frags.length) return;

    final frag = frags[index];
    if (frag.isPinned) {
      frag.clearPinnedTiming();
      debugPrint('[PIN] Fragment $index unlocked');
    } else {
      frag.setPinnedTiming(start: frag.realStart, end: frag.realEnd);
      debugPrint(
        '[PIN] Fragment $index locked at ${frag.realStart.toStringAsFixed(3)}–${frag.realEnd.toStringAsFixed(3)}',
      );
    }

    value = value.copyWith(fragments: frags, hasUnsavedChanges: true);
    await savePinsFile();
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

  Future<void> exportJson() async {
    if (value.fragments.isEmpty) {
      value = value.copyWith(statusMessage: "No data to export.");
      return;
    }

    // 1. Open Save Dialog
    final String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Alignment',
      fileName: 'alignment.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
      lockParentWindow: true,
    );

    if (outputFile == null) return; // User canceled

    try {
      value = value.copyWith(statusMessage: "Exporting...");

      // 2. Convert Fragments to JSON List
      // We manually map fields to ensure clean output (e.g. 3 decimal places)
      final List<Map<String, dynamic>> jsonList = value.fragments
          .map(
            (f) => {
              'index': f.index,
              if (f.id != null) 'id': f.id,
              'text': f.text,
              'start': double.parse(f.realStart.toStringAsFixed(3)),
              'end': double.parse(f.realEnd.toStringAsFixed(3)),
            },
          )
          .toList();

      // 3. Encode with indentation for readability
      final jsonString = const JsonEncoder.withIndent('  ').convert(jsonList);

      // 4. Write to file
      await File(outputFile).writeAsString(jsonString);

      value = value.copyWith(
        statusMessage: "Saved to ${p.basename(outputFile)}",
      );
    } catch (e) {
      value = value.copyWith(statusMessage: "Export failed: $e");
    }
  }

  // --- Playback & Transport ---

  void togglePlay() =>
      value.isPlaying ? _audioService.pause() : _audioService.play();
  void seekTo(Duration d) => _audioService.seek(d);

  void setZoom(double z) {
    final clampedZoom = z.clamp(1.0, 500.0);
    value = value.copyWith(zoomLevel: clampedZoom);
    _settings.setLastZoom(clampedZoom);
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
    Fragment? prevTimed;
    for (int i = index - 1; i >= 0; i--) {
      if (frags[i].realStart >= 0) {
        prevTimed = frags[i];
        break;
      }
    }
    if (prevTimed != null) {
      double prevStart = prevTimed.realStart;
      if (prevStart > s) prevStart = s; // Safety collapse
      prevTimed.setRealTiming(start: prevStart, end: s);
    }

    // 6. Sync Next Fragment (Magnetic End)
    Fragment? nextTimed;
    for (int i = index + 1; i < frags.length; i++) {
      if (frags[i].realStart >= 0) {
        nextTimed = frags[i];
        break;
      }
    }
    if (nextTimed != null) {
      double nextEnd = nextTimed.realEnd;
      if (nextEnd < e) nextEnd = e; // Safety collapse
      nextTimed.setRealTiming(start: e, end: nextEnd);
    }

    // 7. Trigger UI Update
    value = value.copyWith(fragments: frags, hasUnsavedChanges: true);
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

  Future<String> _ensureWavForPlayback(
    String originalPath,
    String ffmpegPath,
  ) async {
    // If it's already a WAV, we don't need to do anything
    if (originalPath.toLowerCase().endsWith('.wav')) return originalPath;

    final tempDir = await getTemporaryDirectory();
    final outPath = p.join(
      tempDir.path,
      '${p.basenameWithoutExtension(originalPath)}_playback.wav',
    );

    // If we already converted this file previously, just return it
    if (await File(outPath).exists()) return outPath;

    // Convert to uncompressed WAV for frame-perfect seeking in just_audio
    value = value.copyWith(statusMessage: "Optimizing audio for playback...");

    final result = await Process.run(ffmpegPath, [
      '-y',
      '-i',
      originalPath,
      '-vn',
      '-acodec',
      'pcm_s16le',
      '-ar',
      '44100',
      '-ac',
      '2',
      outPath,
    ]);

    if (result.exitCode != 0) {
      debugPrint("FFmpeg conversion failed: ${result.stderr}");
      return originalPath; // Fallback to original if it fails
    }

    return outPath;
  }

  // --- MANUAL ALIGNMENT LOGIC ---

  void selectFragment(int? index) {
    value = value.copyWith(selectedFragmentIndex: index);
  }

  Future<void> initManualAlignment() async {
    if (value.textPath == null) return;

    final lines = await File(value.textPath!).readAsLines();
    List<Fragment> frags = [];
    int idx = 0;

    for (var line in lines) {
      if (line.trim().isEmpty) continue;

      String? id;
      String text = line;

      if (value.hasIds) {
        final parts = line.trim().split(' ');
        if (parts.length > 1) {
          id = parts.first;
          text = parts.sublist(1).join(' ');
        } else {
          id = "";
          text = line;
        }
      }

      final f = Fragment(index: idx++, id: id, text: text);
      // Set to "un-timed" state
      f.setRealTiming(start: -1.0, end: -1.0);
      frags.add(f);
    }

    value = value.copyWith(
      fragments: frags,
      hasUnsavedChanges: true,
      selectedFragmentIndex: 0, // Auto-select the first row
      statusMessage: "Manual Setup Complete. Ready to capture.",
    );
  }

  void clearFragmentTiming(int index) {
    final frags = List<Fragment>.from(value.fragments);
    final duration = value.audioDuration.inMilliseconds / 1000.0;

    // Find nearest timed neighbors
    Fragment? prevTimed;
    for (int i = index - 1; i >= 0; i--) {
      if (frags[i].realStart >= 0) {
        prevTimed = frags[i];
        break;
      }
    }
    Fragment? nextTimed;
    for (int i = index + 1; i < frags.length; i++) {
      if (frags[i].realStart >= 0) {
        nextTimed = frags[i];
        break;
      }
    }

    // Heal previous fragment to stretch across the deleted gap
    if (prevTimed != null) {
      double newEnd = nextTimed != null ? nextTimed.realStart : duration;
      prevTimed.setRealTiming(start: prevTimed.realStart, end: newEnd);
    }

    frags[index].setRealTiming(start: -1.0, end: -1.0);
    frags[index].clearPinnedTiming();

    value = value.copyWith(fragments: frags, hasUnsavedChanges: true);
  }

  void captureFragmentTiming(BuildContext context, [int? specificIndex]) {
    final index = specificIndex ?? value.selectedFragmentIndex;
    if (index == null || index < 0 || index >= value.fragments.length) return;

    final frags = List<Fragment>.from(value.fragments);
    final t = value.currentPlaybackPosition.inMilliseconds / 1000.0;
    final duration = value.audioDuration.inMilliseconds / 1000.0;

    Fragment? prevTimed;
    for (int i = index - 1; i >= 0; i--) {
      if (frags[i].realStart >= 0) {
        prevTimed = frags[i];
        break;
      }
    }
    Fragment? nextTimed;
    for (int i = index + 1; i < frags.length; i++) {
      if (frags[i].realStart >= 0) {
        nextTimed = frags[i];
        break;
      }
    }

    // Safety Constraints
    if (prevTimed != null && t <= prevTimed.realStart) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Cannot set time before the previous fragment."),
        ),
      );
      return;
    }
    if (nextTimed != null && t >= nextTimed.realStart) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Cannot set time after the next fragment."),
        ),
      );
      return;
    }

    // Snap times
    double endT = nextTimed != null ? nextTimed.realStart : duration;
    frags[index].setRealTiming(start: t, end: endT);

    if (prevTimed != null) {
      prevTimed.setRealTiming(start: prevTimed.realStart, end: t);
    }

    // Auto-advance to next un-timed fragment
    int? nextIndex;
    for (int i = index + 1; i < frags.length; i++) {
      if (frags[i].realStart < 0) {
        nextIndex = i;
        break;
      }
    }

    value = value.copyWith(
      fragments: frags,
      hasUnsavedChanges: true,
      selectedFragmentIndex: nextIndex,
    );
  }
}

class _AnalysisRequest {
  final String text;
  final Map<String, String> rules;
  final bool hasIds;
  _AnalysisRequest(this.text, this.rules, this.hasIds);
}

class _AnalysisResult {
  final List<String> previewLines;
  final List<String> unknownChars;
  _AnalysisResult(this.previewLines, this.unknownChars);
}

// Top-level function for compute()
_AnalysisResult _analyzeTransliteration(_AnalysisRequest req) {
  final List<String> previewLines = [];
  final Set<String> unknownSet = {};

  // Regex to find non-Latin characters (anything outside ASCII 0-127)
  final nonLatinRegex = RegExp(r'[^\x00-\x7F]');

  // Split text into lines for processing
  final lines = const LineSplitter().convert(req.text);

  int lineCount = 0;
  for (var line in lines) {
    if (line.trim().isEmpty) continue;

    String textToProcess = line;

    // Handle ID stripping logic
    if (req.hasIds) {
      final parts = line.trim().split(' ');
      if (parts.length > 1) {
        textToProcess = parts.sublist(1).join(' ');
      }
    }

    // --- USE CLI LIBRARY HERE ---
    final converted = Transliterator.convert(textToProcess, req.rules);

    // 1. Populate Preview (first 5 lines)
    if (lineCount < 5) {
      previewLines.add(converted);
      lineCount++;
    }

    // 2. Detect Unknowns in the RESULT
    // We scan the *output* string. If there are still non-Latin characters,
    // it means they weren't handled by the dictionary or the stripper.
    // This is actually better for the user: it shows the "base" char they need to map.
    final matches = nonLatinRegex.allMatches(converted);
    for (var m in matches) {
      unknownSet.add(m.group(0)!);
    }
  }

  // Sort list for clean display
  final sortedUnknowns = unknownSet.toList()..sort();
  return _AnalysisResult(previewLines, sortedUnknowns);
}
