import 'dart:typed_data';
import 'package:isochron_cli/isochron_cli.dart'; // From your CLI package

class AppState {
  final bool isProcessing;
  final String statusMessage;
  final double progress;

  final String? audioPath;
  final String? textPath;

  // The alignment results
  final List<Fragment> fragments;

  // Audio visualization data
  final Float64List? waveformData; // Normalized samples -1.0 to 1.0
  final Duration audioDuration;
  final Duration currentPlaybackPosition;
  final bool isPlaying;

  const AppState({
    this.isProcessing = false,
    this.statusMessage = "Select files to begin.",
    this.progress = 0.0,
    this.audioPath,
    this.textPath,
    this.fragments = const [],
    this.waveformData,
    this.audioDuration = Duration.zero,
    this.currentPlaybackPosition = Duration.zero,
    this.isPlaying = false,
  });

  // Helper to copy state with updates
  AppState copyWith({
    bool? isProcessing,
    String? statusMessage,
    double? progress,
    String? audioPath,
    String? textPath,
    List<Fragment>? fragments,
    Float64List? waveformData,
    Duration? audioDuration,
    Duration? currentPlaybackPosition,
    bool? isPlaying,
  }) {
    return AppState(
      isProcessing: isProcessing ?? this.isProcessing,
      statusMessage: statusMessage ?? this.statusMessage,
      progress: progress ?? this.progress,
      audioPath: audioPath ?? this.audioPath,
      textPath: textPath ?? this.textPath,
      fragments: fragments ?? this.fragments,
      waveformData: waveformData ?? this.waveformData,
      audioDuration: audioDuration ?? this.audioDuration,
      currentPlaybackPosition:
          currentPlaybackPosition ?? this.currentPlaybackPosition,
      isPlaying: isPlaying ?? this.isPlaying,
    );
  }
}
