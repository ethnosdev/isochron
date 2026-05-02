import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:file_picker/file_picker.dart';
import 'package:isochron_cli/isochron_cli.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:just_waveform/just_waveform.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'models/app_state.dart';
import '../services/alignment_service.dart';
import '../services/audio_service.dart';
import '../services/pins_service.dart';

class AppManager extends ValueNotifier<AppState> {
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

  AppManager() : super(AppState(zoomLevel: UserSettingsService().lastZoom)) {
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

  Future<void> loadAlignmentPair(AlignmentPair pair, Project project) async {
    _lastSavedPins = null;

    if (value.isPlaying) {
      await _audioService.pause();
    }

    // 1. Resolve Asset Paths from the Pools
    final audioAsset = project.audioPool
        .where((a) => a.id == pair.audioAssetId)
        .firstOrNull;
    final textAsset = project.textPool
        .where((a) => a.id == pair.textAssetId)
        .firstOrNull;
    final dictAsset = project.dictPool
        .where((a) => a.id == pair.dictAssetId)
        .firstOrNull;

    if (audioAsset == null || textAsset == null) {
      value = value.copyWith(
        statusMessage: "Error: Missing Audio or Text asset.",
      );
      return;
    }

    final absJsonPath = pair.getAbsoluteOutputPath(project.directoryPath);
    final playbackPath = await _ensureWavForPlayback(audioAsset.path);
    final duration = await _audioService.load(playbackPath);

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

      await _pinsService.load(absJsonPath, loadedFragments);
      _lastSavedPins = _buildPinsSnapshot(loadedFragments);
    }

    final actualDictPath = dictAsset?.path ?? value.dictPath;
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

    value = value.copyWith(
      audioPath: audioAsset.path,
      textPath: textAsset.path,
      dictPath: actualDictPath,
      transliterationRules: rules,
      autoSavePath: absJsonPath,
      fragments: loadedFragments,
      audioDuration: duration,
      statusMessage: "Loaded ${audioAsset.filename}",
      hasUnsavedChanges: false,
      clearWaveform: true,
      clearFocus: true,
      currentPlaybackPosition: Duration.zero,
    );

    _generateWaveform(audioAsset.path);
  }

  Future<void> saveProject() async {
    if (value.autoSavePath == null) {
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

  Future<void> runAlignment(
    BuildContext context, {
    String snapMode = 'onset',
    int snapOffsetMs = 0,
  }) async {
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
        value = value.copyWith(statusMessage: "Preprocessing text...");

        final lines = await File(value.textPath!).readAsLines();
        final cleanLines = <String>[];

        for (var line in lines) {
          if (line.trim().isEmpty) continue;

          final parts = line.trim().split(' ');
          if (parts.length > 1) {
            extractedIds.add(parts.first);
            cleanLines.add(parts.sublist(1).join(' '));
          } else {
            extractedIds.add("");
            cleanLines.add(line);
          }
        }

        final tempDir = await getTemporaryDirectory();
        tempCleanTextFile = File(p.join(tempDir.path, 'clean_transcript.txt'));
        await tempCleanTextFile.writeAsString(cleanLines.join('\n'));

        actualTextPath = tempCleanTextFile.path;
      }

      final activePinsPath = _pinsPath;
      final passPins =
          activePinsPath != null && await File(activePinsPath).exists();

      List<Fragment> fragments = await _alignmentService.runIsochron(
        textPath: actualTextPath,
        audioPath: value.audioPath!,
        dictPath: value.dictPath,
        pinsPath: passPins ? activePinsPath : null,
        snapMode: snapMode,
        snapOffsetMs: snapOffsetMs,
        onProgress: (status, prog) {
          value = value.copyWith(statusMessage: status, progress: prog);
        },
      );

      // --- POST-PROCESSING ---
      if (value.hasIds && extractedIds.isNotEmpty) {
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

      final previousFragments = value.fragments;
      bool hasAlignmentChanges = previousFragments.length != fragments.length;
      if (!hasAlignmentChanges) {
        for (int i = 0; i < fragments.length; i++) {
          final oldFrag = previousFragments[i];
          final newFrag = fragments[i];
          if (oldFrag.realStart != newFrag.realStart ||
              oldFrag.realEnd != newFrag.realEnd ||
              oldFrag.id != newFrag.id) {
            hasAlignmentChanges = true;
            break;
          }
        }
      }

      value = value.copyWith(
        fragments: fragments,
        statusMessage: "Done.",
        progress: 1.0,
        isProcessing: false,
        hasUnsavedChanges: hasAlignmentChanges || value.hasUnsavedChanges,
      );
    } catch (e) {
      value = value.copyWith(isProcessing: false, statusMessage: "Error: $e");
      if (context.mounted) {
        showMacosAlertDialog(
          context: context,
          builder: (_) => MacosAlertDialog(
            appIcon: const MacosIcon(CupertinoIcons.exclamationmark_triangle),
            title: const Text("Alignment Error"),
            message: Text(e.toString()),
            primaryButton: PushButton(
              controlSize: ControlSize.large,
              onPressed: () => Navigator.pop(context),
              child: const Text("OK"),
            ),
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
    final nextFrag = value.fragments.firstWhere(
      (f) => (f.realStart * 1000) > currentMs + 100,
      orElse: () => value.fragments.last,
    );

    if ((nextFrag.realStart * 1000) > currentMs + 100) {
      seekTo(Duration(milliseconds: (nextFrag.realStart * 1000).toInt()));
    }
  }

  void skipToPrevious() {
    if (value.fragments.isEmpty) return;

    final currentMs = value.currentPlaybackPosition.inMilliseconds;
    final prevFrag = value.fragments.lastWhere(
      (f) => (f.realStart * 1000) < currentMs - 100,
      orElse: () => value.fragments.first,
    );

    seekTo(Duration(milliseconds: (prevFrag.realStart * 1000).toInt()));
  }

  void enterFocusMode(int index) {
    if (value.audioDuration.inMilliseconds == 0) return;

    final totalSeconds = value.audioDuration.inMilliseconds / 1000.0;
    final targetZoom = (totalSeconds / 10.0).clamp(1.0, 500.0);

    final startSeconds = value.fragments[index].realStart;
    seekTo(Duration(milliseconds: (startSeconds * 1000).toInt()));

    value = value.copyWith(zoomLevel: targetZoom, focusedFragmentIndex: index);
  }

  void exitFocusMode() {
    value = value.copyWith(clearFocus: true);
  }

  void setFragmentStartAndPlay(int index, double newStartTime) {
    final frag = value.fragments[index];

    if (newStartTime >= frag.realEnd) return;

    updateFragment(index, newStartTime, frag.realEnd);
    seekTo(Duration(milliseconds: (newStartTime * 1000).toInt()));

    if (!value.isPlaying) {
      _audioService.play();
    }
  }

  int? hoveredFragmentIndex;

  void setHoveredFragmentIndex(int? idx) {
    hoveredFragmentIndex = idx;
  }

  String? get _pinsPath => value.autoSavePath == null
      ? null
      : PinsService.pinsPath(value.autoSavePath!);

  Future<void> savePinsFile() async {
    final path = _pinsPath;
    if (path == null) return;
    await _pinsService.save(value.autoSavePath!, value.fragments);
  }

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

  void lockFragmentsUntil(int index) async {
    final frags = List<Fragment>.from(value.fragments);
    if (index < 0 || index >= frags.length) return;

    for (int i = 0; i <= index; i++) {
      final frag = frags[i];

      frag.setPinnedTiming(start: frag.realStart, end: frag.realEnd);
      debugPrint(
        '[PIN] Fragment $index locked at ${frag.realStart.toStringAsFixed(3)}–${frag.realEnd.toStringAsFixed(3)}',
      );
    }

    value = value.copyWith(fragments: frags, hasUnsavedChanges: true);
    await savePinsFile();
  }

  Future<void> _generateWaveform(String audioPath) async {
    try {
      final tempDir = await getTemporaryDirectory();
      if (!await tempDir.exists()) await tempDir.create(recursive: true);

      final stat = await File(audioPath).stat();
      final fileHash = '${stat.size}_${stat.modified.millisecondsSinceEpoch}';

      final waveFile = File(
        p.join(tempDir.path, '${p.basename(audioPath)}_$fileHash.wave'),
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

    final String? outputFile = await FilePicker.saveFile(
      dialogTitle: 'Export Alignment',
      fileName: 'alignment.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
      lockParentWindow: true,
    );

    if (outputFile == null) return;

    try {
      value = value.copyWith(statusMessage: "Exporting...");

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
      await File(outputFile).writeAsString(jsonString);

      value = value.copyWith(
        statusMessage: "Saved to ${p.basename(outputFile)}",
      );
    } catch (e) {
      value = value.copyWith(statusMessage: "Export failed: $e");
    }
  }

  void togglePlay() =>
      value.isPlaying ? _audioService.pause() : _audioService.play();
  void seekTo(Duration d) => _audioService.seek(d);

  void setZoom(double z) {
    final clampedZoom = z.clamp(1.0, 500.0);
    value = value.copyWith(zoomLevel: clampedZoom);
    _settings.setLastZoom(clampedZoom);
  }

  void updateFragment(int index, double newStart, double newEnd) {
    final frags = List<Fragment>.from(value.fragments);
    final duration = value.audioDuration.inMilliseconds / 1000.0;

    double s = newStart.clamp(0.0, duration);
    double e = newEnd.clamp(0.0, duration);

    if (e <= s + 0.01) {
      if (s != frags[index].realStart) {
        s = e - 0.01;
      } else {
        e = s + 0.01;
      }
    }

    frags[index].setRealTiming(start: s, end: e);

    Fragment? prevTimed;
    for (int i = index - 1; i >= 0; i--) {
      if (frags[i].realStart >= 0) {
        prevTimed = frags[i];
        break;
      }
    }
    if (prevTimed != null) {
      double prevStart = prevTimed.realStart;
      if (prevStart > s) prevStart = s;
      prevTimed.setRealTiming(start: prevStart, end: s);
    }

    Fragment? nextTimed;
    for (int i = index + 1; i < frags.length; i++) {
      if (frags[i].realStart >= 0) {
        nextTimed = frags[i];
        break;
      }
    }
    if (nextTimed != null) {
      double nextEnd = nextTimed.realEnd;
      if (nextEnd < e) nextEnd = e;
      nextTimed.setRealTiming(start: e, end: nextEnd);
    }

    value = value.copyWith(fragments: frags, hasUnsavedChanges: true);
  }

  Future<String> _ensureWavForPlayback(String originalPath) async {
    if (originalPath.toLowerCase().endsWith('.wav')) return originalPath;

    final tempDir = await getTemporaryDirectory();

    final stat = await File(originalPath).stat();
    final fileHash = '${stat.size}_${stat.modified.millisecondsSinceEpoch}';

    final outPath = p.join(
      tempDir.path,
      '${p.basenameWithoutExtension(originalPath)}_${fileHash}_playback.wav',
    );

    if (await File(outPath).exists()) return outPath;

    value = value.copyWith(statusMessage: "Optimizing audio for playback...");

    // Using native macOS afconvert for 44.1kHz Stereo PCM WAV
    final result = await Process.run('/usr/bin/afconvert', [
      '-f',
      'WAVE',
      '-d',
      'LEI16@44100',
      '-c',
      '2',
      originalPath,
      outPath,
    ]);

    if (result.exitCode != 0) {
      debugPrint("afconvert conversion failed: ${result.stderr}");
      return originalPath; // Fallback to original if it fails
    }

    return outPath;
  }

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
      f.setRealTiming(start: -1.0, end: -1.0);
      frags.add(f);
    }

    value = value.copyWith(
      fragments: frags,
      hasUnsavedChanges: true,
      selectedFragmentIndex: 0,
      statusMessage: "Manual Setup Complete. Ready to capture.",
    );
  }

  void clearFragmentTiming(int index) {
    final frags = List<Fragment>.from(value.fragments);
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

    if (prevTimed != null && t <= prevTimed.realStart) {
      showMacosAlertDialog(
        context: context,
        builder: (_) => MacosAlertDialog(
          appIcon: const MacosIcon(CupertinoIcons.exclamationmark_triangle),
          title: const Text("Invalid Timing"),
          message: const Text("Cannot set time before the previous fragment."),
          primaryButton: PushButton(
            controlSize: ControlSize.large,
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ),
      );
      return;
    }
    if (nextTimed != null && t >= nextTimed.realStart) {
      showMacosAlertDialog(
        context: context,
        builder: (_) => MacosAlertDialog(
          appIcon: const MacosIcon(CupertinoIcons.exclamationmark_triangle),
          title: const Text("Invalid Timing"),
          message: const Text("Cannot set time after the next fragment."),
          primaryButton: PushButton(
            controlSize: ControlSize.large,
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ),
      );
      return;
    }

    double endT = nextTimed != null ? nextTimed.realStart : duration;
    frags[index].setRealTiming(start: t, end: endT);

    if (prevTimed != null) {
      prevTimed.setRealTiming(start: prevTimed.realStart, end: t);
    }

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
