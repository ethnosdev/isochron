import 'package:flutter/material.dart';

class WaveformControls extends StatelessWidget {
  final bool isPlaying;
  final double zoom;
  final VoidCallback onPlayPause;
  final VoidCallback? onSkipNext; // Optional, if you want to wire these up
  final VoidCallback? onSkipPrev; // Optional, if you want to wire these up
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: Colors.grey.shade100,
      child: Row(
        children: [
          // --- Transport Controls ---
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

          // --- Zoom Controls ---
          const Icon(Icons.zoom_out, size: 18, color: Colors.grey),
          Expanded(
            child: Slider(
              min: 1.0,
              max: 20.0, // Matching the controller limit
              value: zoom,
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
