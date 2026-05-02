import 'package:isochron_cli/isochron_cli.dart';
import 'package:just_waveform/just_waveform.dart';

class AppState {
  final bool isProcessing;
  final String statusMessage;
  final double progress;
  final String? audioPath;
  final String? textPath;
  final String? dictPath;
  final bool hasIds;
  final List<Fragment> fragments;
  final Waveform? waveform;
  final Duration audioDuration;
  final bool isPlaying;
  final double zoomLevel;
  final int? focusedFragmentIndex;
  final String? autoSavePath;
  final bool hasUnsavedChanges;
  final Map<String, String>? transliterationRules;
  final int? selectedFragmentIndex;

  const AppState({
    this.isProcessing = false,
    this.statusMessage = "Select files to begin.",
    this.progress = 0.0,
    this.audioPath,
    this.textPath,
    this.dictPath,
    this.hasIds = false,
    this.fragments = const [],
    this.waveform,
    this.audioDuration = Duration.zero,
    this.isPlaying = false,
    this.zoomLevel = 1.0,
    this.focusedFragmentIndex,
    this.autoSavePath,
    this.hasUnsavedChanges = false,
    this.transliterationRules,
    this.selectedFragmentIndex,
  });

  AppState copyWith({
    bool? isProcessing,
    String? statusMessage,
    double? progress,
    String? audioPath,
    String? textPath,
    String? dictPath,
    bool? hasIds,
    List<Fragment>? fragments,
    Waveform? waveform,
    bool clearWaveform = false,
    Duration? audioDuration,
    bool? isPlaying,
    double? zoomLevel,
    int? focusedFragmentIndex,
    bool clearFocus = false,
    String? autoSavePath,
    bool? hasUnsavedChanges,
    Map<String, String>? transliterationRules,
    int? selectedFragmentIndex,
    bool clearSelection = false,
  }) {
    return AppState(
      isProcessing: isProcessing ?? this.isProcessing,
      statusMessage: statusMessage ?? this.statusMessage,
      progress: progress ?? this.progress,
      audioPath: audioPath ?? this.audioPath,
      textPath: textPath ?? this.textPath,
      dictPath: dictPath ?? this.dictPath,
      hasIds: hasIds ?? this.hasIds,
      fragments: fragments ?? this.fragments,
      waveform: clearWaveform ? null : (waveform ?? this.waveform),
      audioDuration: audioDuration ?? this.audioDuration,
      isPlaying: isPlaying ?? this.isPlaying,
      zoomLevel: zoomLevel ?? this.zoomLevel,
      focusedFragmentIndex: clearFocus
          ? null
          : (focusedFragmentIndex ?? this.focusedFragmentIndex),
      autoSavePath: autoSavePath ?? this.autoSavePath,
      hasUnsavedChanges: hasUnsavedChanges ?? this.hasUnsavedChanges,
      transliterationRules: transliterationRules ?? this.transliterationRules,
      selectedFragmentIndex: clearSelection
          ? null
          : (selectedFragmentIndex ?? this.selectedFragmentIndex),
    );
  }
}
