import 'package:flutter/material.dart';
import 'package:just_waveform/just_waveform.dart'; // Import package
import 'package:isochron_cli/isochron_cli.dart';
import '../controllers/alignment_controller.dart';
import '../models/app_state.dart';

class WaveformEditor extends StatefulWidget {
  final AlignmentController controller;
  final AppState state;
  final ScrollController scrollController;

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
    // Check for .waveform instead of .waveformData
    if (widget.state.waveform == null) {
      return const Center(child: Text("Generating waveform..."));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final visibleWidth = constraints.maxWidth;
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
              // 1. Seek
              onTapUp: (details) {
                final pct = details.localPosition.dx / contentWidth;
                final ms = (pct * widget.state.audioDuration.inMilliseconds)
                    .toInt();
                widget.controller.seekTo(Duration(milliseconds: ms));
              },
              // 2. Drag Start
              onHorizontalDragStart: (details) {
                _detectHandle(
                  details.localPosition.dx,
                  contentWidth,
                  totalSeconds,
                );
              },
              // 3. Drag Update
              onHorizontalDragUpdate: (details) {
                _updateHandle(
                  details.localPosition.dx,
                  contentWidth,
                  totalSeconds,
                );
              },
              // 4. Drag End
              onHorizontalDragEnd: (_) {
                setState(() => _draggingFragmentIndex = null);
              },
              child: CustomPaint(
                size: Size(contentWidth, height),
                painter: _CombinedPainter(
                  waveform: widget.state.waveform!, // Pass the object
                  fragments: widget.state.fragments,
                  playbackPos:
                      widget.state.currentPlaybackPosition.inMilliseconds /
                      1000.0,
                  totalSeconds: totalSeconds,
                  accentColor: Theme.of(context).primaryColor,
                  zoomLevel: widget.state.zoomLevel,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ... _detectHandle and _updateHandle remain exactly the same ...
  void _detectHandle(double x, double width, double totalDuration) {
    final secondsPerPixel = totalDuration / width;
    final clickTime = x * secondsPerPixel;
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

/// This painter combines the JustWaveform logic with our Editor logic
class _CombinedPainter extends CustomPainter {
  final Waveform waveform;
  final List<Fragment> fragments;
  final double playbackPos;
  final double totalSeconds;
  final Color accentColor;
  final double zoomLevel;

  _CombinedPainter({
    required this.waveform,
    required this.fragments,
    required this.playbackPos,
    required this.totalSeconds,
    required this.accentColor,
    required this.zoomLevel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    // --- LAYER 1: The Waveform (Adapted from JustWaveform example) ---
    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth =
          1.0 // Fine detail
      ..strokeCap = StrokeCap.round
      ..color = Colors.blueGrey.withOpacity(0.6);

    // We draw the *entire* duration onto the *entire* width.
    // just_waveform allows mapping duration to pixels.

    // How many samples are in the entire file?
    final totalSamples = waveform.length;

    // We iterate over the X-axis pixels
    // density: higher zoom = skip fewer samples per pixel
    // To keep performance high on wide canvases, we step by 1 or 2 pixels.
    const double pixelStep = 1.0;

    for (double x = 0; x < width; x += pixelStep) {
      // Map pixel X to Sample Index
      // index = (x / width) * totalSamples
      final sampleIdx = ((x / width) * totalSamples).toInt();

      if (sampleIdx >= 0 && sampleIdx < totalSamples) {
        // Get Amplitude (-1.0 to 1.0 range usually, but just_waveform uses int16 range)
        // just_waveform stores internally as specialized int.
        // We use its helper method `getPixelMin/Max` but we need to map our index correctly.

        // Actually, just_waveform is tricky: .getPixelMin(i) expects 'i' to be a pixel index
        // relative to its internal resolution.
        // Let's use raw data access if possible, OR stick to the logic:

        // Simpler approach using raw values from the wave file logic:
        // just_waveform's [getPixelMin] takes an index based on 'pixelsPerWindow'.
        // Let's rely on the raw int16 values if we can, but the package abstracts them.
        // Let's use normalise() from the example:

        final minY = _normalise(waveform.getPixelMin(sampleIdx), height);
        final maxY = _normalise(waveform.getPixelMax(sampleIdx), height);

        // Draw vertical line for this pixel column
        canvas.drawLine(Offset(x, minY), Offset(x, maxY), wavePaint);
      }
    }

    // --- LAYER 2: Fragments (Bars & Lines) ---
    final paintLine = Paint()
      ..color = accentColor
      ..strokeWidth = 2.0;
    final paintFill = Paint()..color = accentColor.withOpacity(0.15);
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (final frag in fragments) {
      final xStart = (frag.realStart / totalSeconds) * width;
      final xEnd = (frag.realEnd / totalSeconds) * width;

      // Fill
      canvas.drawRect(Rect.fromLTRB(xStart, 0, xEnd, height), paintFill);

      // Lines
      canvas.drawLine(Offset(xStart, 0), Offset(xStart, height), paintLine);
      canvas.drawLine(Offset(xEnd, 0), Offset(xEnd, height), paintLine);

      // Label (#)
      if (xEnd - xStart > 20) {
        textPainter.text = TextSpan(
          text: "${frag.index}",
          style: TextStyle(
            color: accentColor,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(xStart + 5, 5));
      }
    }

    // --- LAYER 3: Playhead ---
    final xPlay = (playbackPos / totalSeconds) * width;
    final paintPlay = Paint()
      ..color = Colors.red
      ..strokeWidth = 2.0;

    canvas.drawLine(Offset(xPlay, 0), Offset(xPlay, height), paintPlay);
    // Draw Triangle Cap
    final pathHead = Path();
    pathHead.moveTo(xPlay - 6, 0);
    pathHead.lineTo(xPlay + 6, 0);
    pathHead.lineTo(xPlay, 8);
    pathHead.close();
    canvas.drawPath(pathHead, Paint()..color = Colors.red);
  }

  // Adapted from just_waveform example
  double _normalise(int s, double height) {
    // 16-bit PCM (flags=0) or 8-bit (flags=1)
    if (waveform.flags == 0) {
      // 16-bit signed (-32768 to 32767)
      final y = 32768 + (s).clamp(-32768.0, 32767.0).toDouble();
      return height - 1 - y * height / 65536;
    } else {
      // 8-bit
      final y = 128 + (s).clamp(-128.0, 127.0).toDouble();
      return height - 1 - y * height / 256;
    }
  }

  @override
  bool shouldRepaint(covariant _CombinedPainter old) => true; // Always repaint on scroll/zoom/play
}
