import 'package:flutter/material.dart';
import 'package:isochron_cli/isochron_cli.dart';
import 'dart:typed_data';
import '../controllers/alignment_controller.dart';
import '../models/app_state.dart';

class WaveformEditor extends StatefulWidget {
  final AlignmentController controller;
  final AppState state;
  final ScrollController scrollController; // Passed from parent

  const WaveformEditor({
    super.key,
    required this.controller,
    required this.state,
    required this.scrollController,
  });

  @override
  State<WaveformEditor> createState() => _WaveformEditorState();
}

class _WaveformEditorState extends State<WaveformEditor> {
  int? _draggingFragmentIndex;
  bool _draggingStart = true;

  @override
  Widget build(BuildContext context) {
    if (widget.state.waveformData == null) {
      return const Center(child: Text("Waveform not available"));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final visibleWidth = constraints.maxWidth;
        // Calculate total scrollable width based on zoom
        final contentWidth = visibleWidth * widget.state.zoomLevel;
        final height = constraints.maxHeight;

        final totalSeconds = widget.state.audioDuration.inMilliseconds / 1000.0;
        if (totalSeconds == 0) return const SizedBox();

        return SingleChildScrollView(
          controller: widget.scrollController,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: contentWidth,
            height: height,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,

              // 1. Seek on Tap
              onTapUp: (details) {
                final pct = details.localPosition.dx / contentWidth;
                final ms = (pct * widget.state.audioDuration.inMilliseconds)
                    .toInt();
                widget.controller.seekTo(Duration(milliseconds: ms));
              },

              // 2. Detect Handle
              onHorizontalDragStart: (details) {
                _detectHandle(
                  details.localPosition.dx,
                  contentWidth,
                  totalSeconds,
                );
              },

              // 3. Move Handle
              onHorizontalDragUpdate: (details) {
                _updateHandle(
                  details.localPosition.dx,
                  contentWidth,
                  totalSeconds,
                );
              },

              // 4. End Drag
              onHorizontalDragEnd: (_) {
                setState(() => _draggingFragmentIndex = null);
              },

              // The Painter
              child: CustomPaint(
                size: Size(contentWidth, height),
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
          ),
        );
      },
    );
  }

  void _detectHandle(double x, double width, double totalDuration) {
    final secondsPerPixel = totalDuration / width;
    final clickTime = x * secondsPerPixel;

    // Detection threshold is tighter when zoomed out, wider when zoomed in?
    // Actually fixed pixel threshold is best.
    // 10 pixels converted to seconds:
    final thresholdSec = 10.0 * secondsPerPixel;

    for (var frag in widget.state.fragments) {
      if ((frag.realStart - clickTime).abs() < thresholdSec) {
        setState(() {
          _draggingFragmentIndex = frag.index;
          _draggingStart = true;
        });
        widget.controller.setDragMode(true);
        return;
      }
      if ((frag.realEnd - clickTime).abs() < thresholdSec) {
        setState(() {
          _draggingFragmentIndex = frag.index;
          _draggingStart = false;
        });
        widget.controller.setDragMode(false);
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

    // Call controller which now handles collision logic
    if (_draggingStart) {
      widget.controller.updateFragmentTiming(frag.index, newTime, frag.realEnd);
    } else {
      widget.controller.updateFragmentTiming(
        frag.index,
        frag.realStart,
        newTime,
      );
    }
  }
}

class _WaveformPainter extends CustomPainter {
  final Float64List waveformData;
  final List<Fragment> fragments;
  final double playbackPos;
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

    // 1. Draw Waveform
    final paintWave = Paint()
      ..color = Colors.blueGrey.withOpacity(0.3)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    final stepX = size.width / waveformData.length;

    path.moveTo(0, midY);
    for (int i = 0; i < waveformData.length; i++) {
      path.lineTo(i * stepX, midY + (waveformData[i] * (size.height / 2)));
    }
    canvas.drawPath(path, paintWave);

    // 2. Draw Fragments
    final paintLine = Paint()
      ..color = accentColor
      ..strokeWidth = 2.0;
    final paintFill = Paint()..color = accentColor.withOpacity(0.1);

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (final frag in fragments) {
      final xStart = (frag.realStart / totalSeconds) * size.width;
      final xEnd = (frag.realEnd / totalSeconds) * size.width;

      // Draw background rect for the segment
      canvas.drawRect(Rect.fromLTRB(xStart, 0, xEnd, size.height), paintFill);

      // Draw Lines
      canvas.drawLine(
        Offset(xStart, 0),
        Offset(xStart, size.height),
        paintLine,
      );
      canvas.drawLine(Offset(xEnd, 0), Offset(xEnd, size.height), paintLine);

      // Draw Index Label (No Verse Text)
      // Only draw if there is space
      if (xEnd - xStart > 15) {
        textPainter.text = TextSpan(
          text: "#${frag.index}",
          style: TextStyle(
            color: accentColor,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        );
        textPainter.layout();
        // Center text in bar
        textPainter.paint(canvas, Offset(xStart + 4, 4));
      }
    }

    // 3. Draw Playhead
    final xPlay = (playbackPos / totalSeconds) * size.width;
    final paintPlay = Paint()
      ..color = Colors.red
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(xPlay, 0), Offset(xPlay, size.height), paintPlay);

    // Draw Playhead "Cap"
    canvas.drawCircle(Offset(xPlay, 0), 5, paintPlay);
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) => true;
}
