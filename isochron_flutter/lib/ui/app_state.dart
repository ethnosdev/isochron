import 'package:isochron_cli/isochron_cli.dart';
import 'package:just_waveform/just_waveform.dart';

class AppState {
  // --- Processing Status ---
  final bool isProcessing;
  final String statusMessage;
  final double progress;

  // --- File Paths ---
  final String? audioPath;
  final String? textPath;
  final String? dictPath;

  // --- Configuration ---
  /// Tracks if the user confirmed the text file contains ID prefixes
  final bool hasIds;

  // --- Data ---
  final List<Fragment> fragments;
  final Waveform? waveform;

  // --- Playback State ---
  final Duration audioDuration;
  final Duration currentPlaybackPosition;
  final bool isPlaying;

  // --- UI View State ---
  final double zoomLevel;
  final int? focusedFragmentIndex;

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
    this.currentPlaybackPosition = Duration.zero,
    this.isPlaying = false,
    this.zoomLevel = 1.0,
    this.focusedFragmentIndex,
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
    Duration? audioDuration,
    Duration? currentPlaybackPosition,
    bool? isPlaying,
    double? zoomLevel,
    int? focusedFragmentIndex,
    bool clearFocus = false,
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
      waveform: waveform ?? this.waveform,
      audioDuration: audioDuration ?? this.audioDuration,
      currentPlaybackPosition:
          currentPlaybackPosition ?? this.currentPlaybackPosition,
      isPlaying: isPlaying ?? this.isPlaying,
      zoomLevel: zoomLevel ?? this.zoomLevel,
      focusedFragmentIndex: clearFocus
          ? null
          : (focusedFragmentIndex ?? this.focusedFragmentIndex),
    );
  }
}
