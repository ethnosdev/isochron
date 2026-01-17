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
    // Dynamic Max: If zoom is high (Focus Mode), expand the slider range.
    // Otherwise, keep it at 20x for finer control during normal use.
    final double sliderMax = (zoom > 20.0) ? zoom : 20.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: Colors.grey.shade100,
      child: Row(
        children: [
          // --- Transport ---
          IconButton(
            icon: const Icon(Icons.skip_previous),
            onPressed: onSkipPrev,
            tooltip: "Previous Segment",
          ),
          IconButton(
            icon: Icon(
              isPlaying ? Icons.pause_circle : Icons.play_circle,
              size: 40,
              color: Colors.teal,
            ),
            onPressed: onPlayPause,
            tooltip: isPlaying ? "Pause" : "Play",
          ),
          IconButton(
            icon: const Icon(Icons.skip_next),
            onPressed: onSkipNext,
            tooltip: "Next Segment",
          ),

          const SizedBox(width: 20),
          Container(width: 1, height: 24, color: Colors.grey.shade400),
          const SizedBox(width: 20),

          // --- Zoom ---
          const Icon(Icons.zoom_out, size: 18, color: Colors.grey),
          Expanded(
            child: Slider(
              min: 1.0,
              max: sliderMax, // <--- FIXED HERE
              value: zoom.clamp(1.0, sliderMax), // Double safety
              label: "${zoom.toStringAsFixed(1)}x",
              onChanged: onZoom,
              activeColor: Colors.teal,
            ),
          ),
          const Icon(Icons.zoom_in, size: 18, color: Colors.grey),
        ],
      ),
    );
  }
}
