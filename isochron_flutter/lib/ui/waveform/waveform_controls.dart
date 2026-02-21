import 'package:flutter/material.dart';

class WaveformControls extends StatelessWidget {
  final bool isPlaying;
  final double zoom;
  final VoidCallback onPlayPause;
  final VoidCallback? onSkipNext;
  final VoidCallback? onSkipPrev;
  final ValueChanged<double> onZoom;

  const WaveformControls({
    super.key,
    required this.isPlaying,
    required this.zoom,
    required this.onPlayPause,
    required this.onZoom,
    this.onSkipNext,
    this.onSkipPrev,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final double sliderMax = (zoom > 20.0) ? zoom : 20.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      // Automatically changes from a soft grey in light mode to dark grey in dark mode
      color: colorScheme.surfaceContainer,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.skip_previous),
            onPressed: onSkipPrev,
            color: colorScheme.onSurfaceVariant,
            tooltip: "Previous Segment",
          ),
          IconButton(
            icon: Icon(
              isPlaying ? Icons.pause_circle : Icons.play_circle,
              size: 40,
              color: colorScheme.primary, // Adapts to theme's primary
            ),
            onPressed: onPlayPause,
            tooltip: isPlaying ? "Pause" : "Play",
          ),
          IconButton(
            icon: const Icon(Icons.skip_next),
            onPressed: onSkipNext,
            color: colorScheme.onSurfaceVariant,
            tooltip: "Next Segment",
          ),

          const SizedBox(width: 20),
          Container(
            width: 1,
            height: 24,
            color: Theme.of(context).dividerColor,
          ),
          const SizedBox(width: 20),

          Icon(Icons.zoom_out, size: 18, color: colorScheme.onSurfaceVariant),
          Expanded(
            child: Slider(
              min: 1.0,
              max: sliderMax,
              value: zoom.clamp(1.0, sliderMax),
              label: "${zoom.toStringAsFixed(1)}x",
              onChanged: onZoom,
              activeColor: colorScheme.primary,
              inactiveColor: colorScheme.surfaceContainerHighest,
            ),
          ),
          Icon(Icons.zoom_in, size: 18, color: colorScheme.onSurfaceVariant),
        ],
      ),
    );
  }
}
