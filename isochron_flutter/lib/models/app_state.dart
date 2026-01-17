import 'package:isochron_cli/isochron_cli.dart';
import 'package:just_waveform/just_waveform.dart'; // From your CLI package

class AppState {
  final bool isProcessing;
  final String statusMessage;
  final double progress;

  final String? audioPath;
  final String? textPath;
  final String? dictPath;

  // The alignment results
  final List<Fragment> fragments;

  // Audio visualization data
  final Waveform? waveform;
  final Duration audioDuration;
  final Duration currentPlaybackPosition;
  final bool isPlaying;
  final double zoomLevel;

  const AppState({
    this.isProcessing = false,
    this.statusMessage = "Select files to begin.",
    this.progress = 0.0,
    this.audioPath,
    this.textPath,
    this.dictPath,
    this.fragments = const [],
    this.waveform,
    this.audioDuration = Duration.zero,
    this.currentPlaybackPosition = Duration.zero,
    this.isPlaying = false,
    this.zoomLevel = 1.0,
  });

  // Helper to copy state with updates
  AppState copyWith({
    bool? isProcessing,
    String? statusMessage,
    double? progress,
    String? audioPath,
    String? textPath,
    String? dictPath,
    List<Fragment>? fragments,
    Waveform? waveform,
    Duration? audioDuration,
    Duration? currentPlaybackPosition,
    bool? isPlaying,
    double? zoomLevel,
  }) {
    return AppState(
      isProcessing: isProcessing ?? this.isProcessing,
      statusMessage: statusMessage ?? this.statusMessage,
      progress: progress ?? this.progress,
      audioPath: audioPath ?? this.audioPath,
      textPath: textPath ?? this.textPath,
      dictPath: dictPath ?? this.dictPath,
      fragments: fragments ?? this.fragments,
      waveform: waveform ?? this.waveform,
      audioDuration: audioDuration ?? this.audioDuration,
      currentPlaybackPosition:
          currentPlaybackPosition ?? this.currentPlaybackPosition,
      isPlaying: isPlaying ?? this.isPlaying,
      zoomLevel: zoomLevel ?? this.zoomLevel,
    );
  }
}
