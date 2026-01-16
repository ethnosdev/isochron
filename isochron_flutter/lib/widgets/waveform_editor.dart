import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:isochron_cli/isochron_cli.dart';
import '../controllers/alignment_controller.dart';
import '../models/app_state.dart';

class WaveformEditor extends StatefulWidget {
  final AlignmentController controller;
  final AppState state;

  const WaveformEditor({
    super.key,
    required this.controller,
    required this.state,
  });

  @override
  State<WaveformEditor> createState() => _WaveformEditorState();
}

class _WaveformEditorState extends State<WaveformEditor> {
  // To handle dragging
  int? _draggingFragmentIndex;
  bool _draggingStart = true; // true = start handle, false = end handle

  @override
  Widget build(BuildContext context) {
    if (widget.state.waveformData == null) {
      return Container(
        height: 200,
        color: Colors.grey[200],
        child: const Center(child: Text("Waveform not available")),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = 200.0;
        final totalSeconds = widget.state.audioDuration.inMilliseconds / 1000.0;

        // Avoid division by zero
        if (totalSeconds == 0) return const SizedBox();

        return SizedBox(
          height: height,
          width: width,
          child: GestureDetector(
            // 1. Handle clicks to seek
            onTapUp: (details) {
              final pct = details.localPosition.dx / width;
              final ms = (pct * widget.state.audioDuration.inMilliseconds)
                  .toInt();
              widget.controller.seekTo(Duration(milliseconds: ms));
            },
            // 2. Handle dragging handles
            onHorizontalDragStart: (details) {
              _detectHandle(details.localPosition.dx, width, totalSeconds);
            },
            onHorizontalDragUpdate: (details) {
              _updateHandle(details.localPosition.dx, width, totalSeconds);
            },
            onHorizontalDragEnd: (_) {
              setState(() {
                _draggingFragmentIndex = null;
              });
            },
            child: CustomPaint(
              painter: _WaveformPainter(
                waveformData: widget.state.waveformData!,
                fragments: widget.state.fragments,
                playbackPos:
                    widget.state.currentPlaybackPosition.inMilliseconds /
                    1000.0,
                totalSeconds: totalSeconds,
                accentColor: Theme.of(context).primaryColor,
              ),
            ),
          ),
        );
      },
    );
  }

  void _detectHandle(double x, double width, double totalDuration) {
    // Find if user clicked near a start or end line
    final secondsPerPixel = totalDuration / width;
    final clickTime = x * secondsPerPixel;
    const threshold = 0.5; // Detection threshold in seconds

    for (var frag in widget.state.fragments) {
      if ((frag.realStart - clickTime).abs() < threshold) {
        setState(() {
          _draggingFragmentIndex = frag.index;
          _draggingStart = true;
        });
        return;
      }
      if ((frag.realEnd - clickTime).abs() < threshold) {
        setState(() {
          _draggingFragmentIndex = frag.index;
          _draggingStart = false;
        });
        return;
      }
    }
  }

  void _updateHandle(double x, double width, double totalDuration) {
    if (_draggingFragmentIndex == null) return;

    final secondsPerPixel = totalDuration / width;
    final newTime = (x * secondsPerPixel).clamp(0.0, totalDuration);

    final frag = widget.state.fragments.firstWhere(
      (f) => f.index == _draggingFragmentIndex,
    );

    // Update via controller
    if (_draggingStart) {
      // Ensure start doesn't pass end
      if (newTime < frag.realEnd) {
        widget.controller.updateFragmentTiming(
          frag.index,
          newTime,
          frag.realEnd,
        );
      }
    } else {
      // Ensure end doesn't go before start
      if (newTime > frag.realStart) {
        widget.controller.updateFragmentTiming(
          frag.index,
          frag.realStart,
          newTime,
        );
      }
    }
  }
}

class _WaveformPainter extends CustomPainter {
  final Float64List waveformData;
  final List<Fragment> fragments;
  final double playbackPos; // in seconds
  final double totalSeconds;
  final Color accentColor;

  _WaveformPainter({
    required this.waveformData,
    required this.fragments,
    required this.playbackPos,
    required this.totalSeconds,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final paintWave = Paint()
      ..color = Colors.blueGrey.withOpacity(0.5)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // 1. Draw Waveform
    // Simple algorithm: Draw lines between points mapped to width
    final path = Path();
    final stepX = size.width / waveformData.length;

    path.moveTo(0, midY);
    for (int i = 0; i < waveformData.length; i++) {
      final x = i * stepX;
      final y = midY + (waveformData[i] * (size.height / 2));
      path.lineTo(x, y);
    }
    canvas.drawPath(path, paintWave);

    // 2. Draw Fragments Regions (Start/End lines)
    final paintLine = Paint()
      ..color = accentColor
      ..strokeWidth = 2.0;

    final paintText = TextPainter(textDirection: TextDirection.ltr);

    for (final frag in fragments) {
      final xStart = (frag.realStart / totalSeconds) * size.width;
      final xEnd = (frag.realEnd / totalSeconds) * size.width;

      // Draw Start Line
      canvas.drawLine(
        Offset(xStart, 0),
        Offset(xStart, size.height),
        paintLine,
      );

      // Draw End Line (Optional, or just connect them with a rect)
      canvas.drawLine(Offset(xEnd, 0), Offset(xEnd, size.height), paintLine);

      // Draw Text Label overlay
      if (xEnd - xStart > 20) {
        // Only draw if wide enough
        paintText.text = TextSpan(
          text: frag.text,
          style: const TextStyle(color: Colors.black87, fontSize: 10),
        );
        paintText.layout(maxWidth: xEnd - xStart);
        paintText.paint(canvas, Offset(xStart + 5, 10));
      }
    }

    // 3. Draw Playhead
    final xPlay = (playbackPos / totalSeconds) * size.width;
    final paintPlay = Paint()
      ..color = Colors.red
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(xPlay, 0), Offset(xPlay, size.height), paintPlay);
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.playbackPos != playbackPos ||
        oldDelegate.fragments != fragments;
  }
}
