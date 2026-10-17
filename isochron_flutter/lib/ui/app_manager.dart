import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:isochron_cli/isochron_cli.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'package:isochron_flutter/utils/id_extraction.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_waveform/just_waveform.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'models/app_state.dart';
import '../services/alignment_service.dart';
import '../services/audio_service.dart';

class AppManager extends ValueNotifier<AppState> {
  final AudioService _audioService = AudioService();
  final AlignmentService _alignmentService = AlignmentService();
  final _settings = UserSettingsService();
  VoidCallback? onSaveCallback;

  // Callback to notify that a track has completed alignment in the background
  void Function(String trackId, List<Fragment> fragments)?
  onBackgroundAlignmentComplete;

  final playbackPosition = ValueNotifier(Duration.zero);
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<PlayerState>? _stateSub;
  int? _stopPlaybackAtMs;
  int? _resetPlaybackToMs;
  int? _resettingToMs;
  Timer? _stopPlaybackTimer;
  Timer? _resettingTimeoutTimer;
  Timer? _nudgeDebounceTimer;

  AppManager() : super(AppState(zoomLevel: UserSettingsService().lastZoom)) {
    _posSub = _audioService.positionStream.listen(handleAudioPosition);
    _stateSub = _audioService.stateStream.listen((s) {
      value = value.copyWith(isPlaying: s.playing);
    });
  }

  void _cancelFragmentPlayback() {
    _resettingToMs = null;
    _resettingTimeoutTimer?.cancel();
    _resettingTimeoutTimer = null;
    _stopPlaybackTimer?.cancel();
    _stopPlaybackTimer = null;
    _stopPlaybackAtMs = null;
    _resetPlaybackToMs = null;
  }

  void _onFragmentPlaybackComplete() {
    final resetMs = _resetPlaybackToMs;
    _stopPlaybackTimer?.cancel();
    _stopPlaybackTimer = null;
    _stopPlaybackAtMs = null;
    _resetPlaybackToMs = null;
    _audioService.pause();
    if (resetMs != null) {
      _resettingToMs = resetMs;
      _resettingTimeoutTimer?.cancel();
      _resettingTimeoutTimer = Timer(const Duration(milliseconds: 500), () {
        _resettingToMs = null;
        _resettingTimeoutTimer = null;
      });
      seekTo(Duration(milliseconds: resetMs), isInternalReset: true);
      playbackPosition.value = Duration(milliseconds: resetMs);
    }
  }

  @visibleForTesting
  void handleAudioPosition(Duration pos) {
    if (_resettingToMs != null) {
      if ((pos.inMilliseconds - _resettingToMs!).abs() <= 50) {
        _resettingToMs = null;
        _resettingTimeoutTimer?.cancel();
        _resettingTimeoutTimer = null;
        playbackPosition.value = pos;
      }
      return;
    }
    if (_stopPlaybackAtMs != null && pos.inMilliseconds >= _stopPlaybackAtMs!) {
      _onFragmentPlaybackComplete();
      return;
    }
    playbackPosition.value = pos;
  }

  @override
  void dispose() {
    _nudgeDebounceTimer?.cancel();
    _nudgeDebounceTimer = null;
    _cancelFragmentPlayback();
    _posSub?.cancel();
    _stateSub?.cancel();
    _audioService.dispose();
    playbackPosition.dispose();
    super.dispose();
  }

  Future<void> loadTrack(Track track, Project project) async {
    await flushPendingAutoSave();
    _cancelFragmentPlayback();
    if (value.isPlaying) {
      await _audioService.pause();
    }

    // Lookup the track's parent collection to retrieve its folder name
    final collection = project.collections.firstWhere(
      (c) => c.id == track.collectionId,
      orElse: () => Collection(id: track.collectionId, name: 'Default'),
    );
    final String folderName = collection.folderName;

    final resolvedAudio = track.getResolvedAudioPath(
      project.directoryPath,
      folderName,
    );
    final resolvedText = track.getResolvedTextPath(
      project.directoryPath,
      folderName,
    );

    if (resolvedAudio == null || resolvedText == null) {
      value = value.copyWith(
        statusMessage: "Error: Missing Audio or Text file in Track.",
      );
      return;
    }

    final absJsonPath = track.getAbsoluteOutputPath(
      project.directoryPath,
      folderName,
    );

    final playbackPath = await _ensureWavForPlayback(resolvedAudio);
    final duration = await _audioService.load(playbackPath);

    List<Fragment> loadedFragments = [];
    if (await File(absJsonPath).exists()) {
      try {
        final content = await File(absJsonPath).readAsString();
        final List<dynamic> jsonList = jsonDecode(content);
        loadedFragments = jsonList
            .map((j) => Fragment.fromJson(j as Map<String, dynamic>))
            .toList();
      } catch (e) {
        debugPrint('[LOAD] Failed to parse existing alignment JSON: $e');
      }
    }

    bool effectiveHasIds = project.defaultHasIds;
    if (!effectiveHasIds && File(resolvedText).existsSync()) {
      try {
        final sample = File(resolvedText).readAsStringSync();
        if (detectTabDelimitedIds(sample)) {
          effectiveHasIds = true;
        }
      } catch (_) {}
    }

    value = value.copyWith(
      audioPath: resolvedAudio,
      textPath: resolvedText,
      autoSavePath: absJsonPath,
      fragments: loadedFragments,
      hasIds: effectiveHasIds,
      audioDuration: duration,
      statusMessage: "Loaded ${track.name}",
      hasUnsavedChanges: false,
      clearWaveform: true,
      clearFocus: true,
    );
    playbackPosition.value = Duration.zero;

    _generateWaveform(resolvedAudio);

    if (loadedFragments.isEmpty) {
      await initManualAlignment();
    }
  }

  void scheduleNudgeAutoSave() {
    _nudgeDebounceTimer?.cancel();
    _nudgeDebounceTimer = Timer(const Duration(seconds: 1), () {
      saveProject();
    });
  }

  Future<void> flushPendingAutoSave() async {
    _nudgeDebounceTimer?.cancel();
    _nudgeDebounceTimer = null;
    if (value.hasUnsavedChanges) {
      await saveProject();
    }
  }

  Future<void> saveProject() async {
    _nudgeDebounceTimer?.cancel();
    _nudgeDebounceTimer = null;

    if (value.autoSavePath == null) {
      return;
    }

    if (value.fragments.isEmpty) return;

    try {
      final jsonList = value.fragments.map((f) => f.toJson()).toList();
      final jsonString = const JsonEncoder.withIndent('  ').convert(jsonList);

      final outFile = File(value.autoSavePath!);
      if (!await outFile.parent.exists()) {
        await outFile.parent.create(recursive: true);
      }

      final tempFile = File('${value.autoSavePath!}.tmp');
      await tempFile.writeAsString(jsonString);
      await tempFile.rename(outFile.path);

      value = value.copyWith(hasUnsavedChanges: false);
      onSaveCallback?.call();
    } catch (e) {
      debugPrint('[AUTOSAVE] Save failed: $e');
    }
  }

  Future<void> discardChanges() async {
    if (value.autoSavePath != null && await File(value.autoSavePath!).exists()) {
      try {
        final content = await File(value.autoSavePath!).readAsString();
        final List<dynamic> jsonList = jsonDecode(content);
        final loaded = jsonList
            .map((j) => Fragment.fromJson(j as Map<String, dynamic>))
            .toList();
        value = value.copyWith(fragments: loaded, hasUnsavedChanges: false);
      } catch (e) {
        debugPrint('[DISCARD] Failed to reload saved alignment: $e');
        value = value.copyWith(hasUnsavedChanges: false);
      }
    } else {
      value = value.copyWith(hasUnsavedChanges: false);
    }
  }

  Future<void> runAlignment({
    required String trackId,
    String? languageCode,
    double leadInSeconds = 0.19,
    bool keepEdits = false,
  }) async {
    if (value.audioPath == null || value.textPath == null) return;

    final String initiatingTrackId = trackId;
    final String initiatingAudioPath = value.audioPath!;
    final String initiatingTextPath = value.textPath!;
    final String? initiatingSavePath = value.autoSavePath;
    final bool initiatingHasIds = value.hasIds;

    // Write backup file if alignment output already exists
    if (initiatingSavePath != null && await File(initiatingSavePath).exists()) {
      try {
        await File(initiatingSavePath).copy('$initiatingSavePath.bak');
        debugPrint('[BACKUP] Created alignment backup at $initiatingSavePath.bak');
      } catch (_) {}
    }

    value = value.copyWith(
      isProcessing: true,
      progress: 0.0,
      statusMessage: "Starting MMS neural aligner...",
    );

    try {
      final fragments = await _alignmentService.align(
        textPath: initiatingTextPath,
        audioPath: initiatingAudioPath,
        languageCode: languageCode,
        leadInSeconds: leadInSeconds,
        hasIds: initiatingHasIds,
        keepEdits: keepEdits,
        existingFragments: keepEdits ? value.fragments : null,
        onProgress: (status, prog) {
          if (value.autoSavePath == initiatingSavePath) {
            value = value.copyWith(statusMessage: status, progress: prog);
          }
        },
      );

      final bool isStillActive = (value.autoSavePath == initiatingSavePath);

      if (isStillActive) {
        if (value.waveform == null) {
          await _generateWaveform(initiatingAudioPath);
        }

        value = value.copyWith(
          fragments: fragments,
          statusMessage: "Done.",
          progress: 1.0,
          isProcessing: false,
          hasUnsavedChanges: false,
        );
        await saveProject();
      } else {
        // Track has changed (Background alignment completed). Write results directly to its JSON output.
        if (initiatingSavePath != null) {
          final jsonList = fragments.map((f) => f.toJson()).toList();
          final jsonString = const JsonEncoder.withIndent('  ').convert(jsonList);
          final outFile = File(initiatingSavePath);
          if (!await outFile.parent.exists()) {
            await outFile.parent.create(recursive: true);
          }
          await outFile.writeAsString(jsonString);
          debugPrint(
            "[ALIGN] Background alignment completed and saved directly for: $initiatingSavePath",
          );
        }
      }

      onBackgroundAlignmentComplete?.call(initiatingTrackId, fragments);
    } catch (e) {
      if (value.autoSavePath == initiatingSavePath) {
        value = value.copyWith(isProcessing: false, statusMessage: "Error: $e");
      }
      rethrow;
    }
  }

  void skipToNext() {
    if (value.fragments.isEmpty) return;

    final currentMs = playbackPosition.value.inMilliseconds;
    final nextFrag = value.fragments.firstWhere(
      (f) => (f.realStart * 1000) > currentMs + 100,
      orElse: () => value.fragments.last,
    );

    if ((nextFrag.realStart * 1000) > currentMs + 100) {
      seekTo(Duration(milliseconds: (nextFrag.realStart * 1000).ceil()));
    }
  }

  void skipToPrevious() {
    if (value.fragments.isEmpty) return;

    final currentMs = playbackPosition.value.inMilliseconds;
    final prevFrag = value.fragments.lastWhere(
      (f) => (f.realStart * 1000) < currentMs - 300,
      orElse: () => value.fragments.first,
    );

    seekTo(Duration(milliseconds: (prevFrag.realStart * 1000).ceil()));
  }

  void enterFocusMode(int index) {
    if (value.audioDuration.inMilliseconds == 0) return;

    final totalSeconds = value.audioDuration.inMilliseconds / 1000.0;
    final targetZoom = (totalSeconds / 10.0).clamp(1.0, 500.0);

    final startSeconds = value.fragments[index].realStart;

    seekTo(Duration(milliseconds: (startSeconds * 1000).ceil()));

    value = value.copyWith(zoomLevel: targetZoom, focusedFragmentIndex: index);
  }

  void exitFocusMode() {
    value = value.copyWith(clearFocus: true);
  }

  void setFragmentStartAndPlay(int index, double newStartTime) {
    final frag = value.fragments[index];

    if (newStartTime >= frag.realEnd) return;

    updateFragment(index, newStartTime, frag.realEnd);
    seekTo(Duration(milliseconds: (newStartTime * 1000).ceil()));

    if (!value.isPlaying) {
      _audioService.play();
    }
  }

  int? hoveredFragmentIndex;

  void setHoveredFragmentIndex(int? idx) {
    hoveredFragmentIndex = idx;
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
      initialDirectory: value.autoSavePath != null
          ? p.dirname(value.autoSavePath!)
          : null,
    );

    if (outputFile == null) return;

    try {
      value = value.copyWith(statusMessage: "Exporting...");

      final jsonList = value.fragments.map((f) => f.toJson()).toList();
      final jsonString = const JsonEncoder.withIndent('  ').convert(jsonList);

      final file = File(outputFile);
      await file.writeAsString(jsonString);

      value = value.copyWith(
        statusMessage: "Exported successfully to: ${p.basename(outputFile)}",
      );
    } catch (e) {
      value = value.copyWith(statusMessage: "Export failed: $e");
    }
  }

  void togglePlay() {
    _cancelFragmentPlayback();
    value.isPlaying ? _audioService.pause() : _audioService.play();
  }

  void seekTo(Duration d, {bool isInternalReset = false}) {
    if (!isInternalReset) {
      _cancelFragmentPlayback();
    } else {
      _stopPlaybackTimer?.cancel();
      _stopPlaybackTimer = null;
      _stopPlaybackAtMs = null;
      _resetPlaybackToMs = null;
    }
    _audioService.seek(d);
  }

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

    final oldFrag = frags[index];
    final autoStart = oldFrag.autoStart ?? oldFrag.realStart;

    frags[index] = oldFrag.copyWith(
      realStart: s,
      realEnd: e,
      autoStart: autoStart,
      status: FragmentStatus.edited,
    );

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

  int? _latchedNudgeFragmentIndex;

  /// Returns true if Cmd (on macOS) or Ctrl (on other platforms) is currently pressed.
  bool _isModifierPressed() {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.meta) ||
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight) ||
        keys.contains(LogicalKeyboardKey.control) ||
        keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);
  }

  /// Clears any latched fragment index for nudge operations.
  void clearNudgeLatch() {
    _latchedNudgeFragmentIndex = null;
  }

  /// Nudges the active boundary by [deltaSeconds] and seeks directly to the new boundary position.
  /// If audio was playing, it continues playing immediately from that position; if paused,
  /// it updates the playhead position without starting playback.
  void nudgeActiveBoundary(double deltaSeconds) {
    if (value.fragments.isEmpty) return;

    if (!_isModifierPressed()) {
      _latchedNudgeFragmentIndex = null;
    }

    int? idx = _latchedNudgeFragmentIndex;
    if (idx == null || idx < 0 || idx >= value.fragments.length) {
      final currentSec = playbackPosition.value.inMilliseconds / 1000.0;
      final playheadIdx = value.fragments.indexWhere(
        (f) =>
            f.realStart >= 0 &&
            currentSec >= f.realStart &&
            currentSec < f.realEnd,
      );
      if (playheadIdx != -1) {
        idx = playheadIdx;
      } else {
        idx = value.selectedFragmentIndex;
      }
    }

    if (idx == null || idx < 0 || idx >= value.fragments.length) return;
    _latchedNudgeFragmentIndex = idx;

    final frag = value.fragments[idx];
    if (frag.realStart < 0) return;

    final newStart = frag.realStart + deltaSeconds;
    updateFragment(idx, newStart, frag.realEnd);

    if (value.selectedFragmentIndex != idx) {
      value = value.copyWith(selectedFragmentIndex: idx);
    }

    final newStartMs = (newStart * 1000).clamp(0.0, double.infinity).toInt();
    seekTo(Duration(milliseconds: newStartMs));
    if (value.isPlaying) {
      _audioService.play();
    }
    scheduleNudgeAutoSave();
  }

  /// Plays only the current fragment (from realStart to realEnd) and then stops,
  /// resetting the playhead to the beginning of the fragment when finished.
  void playCurrentFragment() {
    _cancelFragmentPlayback();

    final currentSec = playbackPosition.value.inMilliseconds / 1000.0;
    int? idx = value.fragments.indexWhere(
      (f) =>
          f.realStart >= 0 &&
          currentSec >= f.realStart &&
          currentSec < f.realEnd,
    );
    if (idx == -1) {
      idx = value.selectedFragmentIndex;
    }

    if (idx == null || idx < 0 || idx >= value.fragments.length) return;
    final frag = value.fragments[idx];
    if (frag.realStart < 0 || frag.realEnd <= frag.realStart) return;

    final startMs = (frag.realStart * 1000).ceil();
    final endMs = (frag.realEnd * 1000).ceil();
    final durationMs = endMs - startMs;
    if (durationMs <= 0) return;

    seekTo(Duration(milliseconds: startMs));
    playbackPosition.value = Duration(milliseconds: startMs);
    _stopPlaybackAtMs = endMs;
    _resetPlaybackToMs = startMs;
    _audioService.play();

    _stopPlaybackTimer = Timer(Duration(milliseconds: durationMs + 100), () {
      if (_stopPlaybackAtMs != null) {
        _onFragmentPlaybackComplete();
      }
    });
  }

  /// Marks verse as reviewed and advances to next verse.
  void markReviewedAndAdvance() {
    final currentSec = playbackPosition.value.inMilliseconds / 1000.0;
    int? idx = value.fragments.indexWhere(
      (f) =>
          f.realStart >= 0 &&
          currentSec >= f.realStart &&
          currentSec < f.realEnd,
    );
    if (idx == -1) {
      idx = value.selectedFragmentIndex;
    }

    if (idx == null || idx < 0 || idx >= value.fragments.length) return;
    final frags = List<Fragment>.from(value.fragments);
    frags[idx] = frags[idx].copyWith(status: FragmentStatus.reviewed);

    final nextIndex = idx + 1 < frags.length ? idx + 1 : null;
    value = value.copyWith(
      fragments: frags,
      hasUnsavedChanges: true,
      selectedFragmentIndex: nextIndex,
    );

    if (nextIndex != null && frags[nextIndex].realStart >= 0) {
      seekTo(Duration(milliseconds: (frags[nextIndex].realStart * 1000).ceil()));
    }
    saveProject();
  }

  /// Jumps to the next verse with diagnostic anomaly flags, wrapping around the track.
  void jumpToNextFlaggedVerse() {
    if (value.fragments.isEmpty) return;
    final currentIdx = value.selectedFragmentIndex ?? -1;
    final total = value.fragments.length;

    for (int offset = 1; offset <= total; offset++) {
      final idx = (currentIdx + offset) % total;
      final frag = value.fragments[idx];
      if (frag.flags.isNotEmpty) {
        selectFragment(idx);
        if (frag.realStart >= 0) {
          seekTo(Duration(milliseconds: (frag.realStart * 1000).toInt()));
        }
        return;
      }
    }
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
      return originalPath;
    }

    return outPath;
  }

  void selectFragment(int? index) {
    clearNudgeLatch();
    value = value.copyWith(selectedFragmentIndex: index);
  }

  Future<void> initManualAlignment() async {
    if (value.textPath == null) return;
    final lines = await File(value.textPath!).readAsLines();
    final frags = <Fragment>[];
    int idx = 0;

    for (var line in lines) {
      if (line.trim().isEmpty) continue;
      String? id;
      String content = line;

      if (value.hasIds) {
        final parsed = extractIdFromLine(line);
        id = parsed.hasId ? parsed.id : null;
        content = parsed.content;
      }

      frags.add(
        Fragment(
          index: idx++,
          id: id,
          text: content,
          status: FragmentStatus.legacy,
        )..setRealTiming(start: -1.0, end: -1.0),
      );
    }

    value = value.copyWith(fragments: frags, hasUnsavedChanges: false);
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

    frags[index] = frags[index].copyWith(
      realStart: -1.0,
      realEnd: -1.0,
      status: FragmentStatus.edited,
    );

    value = value.copyWith(fragments: frags, hasUnsavedChanges: true);
    saveProject();
  }

  void captureFragmentTiming(BuildContext context, [int? specificIndex]) {
    final index = specificIndex ?? value.selectedFragmentIndex;
    if (index == null || index < 0 || index >= value.fragments.length) return;

    final frags = List<Fragment>.from(value.fragments);
    final t = playbackPosition.value.inMilliseconds / 1000.0;
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
    final oldFrag = frags[index];
    final autoStart = oldFrag.autoStart ?? (oldFrag.realStart >= 0 ? oldFrag.realStart : null);

    frags[index] = oldFrag.copyWith(
      realStart: t,
      realEnd: endT,
      autoStart: autoStart,
      status: FragmentStatus.edited,
    );

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
    saveProject();
  }
}
