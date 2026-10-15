import 'package:flutter/material.dart';
import 'package:just_waveform/just_waveform.dart';
import 'package:isochron_cli/isochron_cli.dart';

class IsochronWaveformPainter extends CustomPainter {
  final Waveform waveform;
  final List<Fragment> fragments;
  final double playbackPosSeconds;
  final double totalSeconds;
  final double zoomLevel;
  final int? activeFragmentIndex;

  // --- Dynamic Theme Colors ---
  final Color accentColor;
  final Color waveColor;
  final Color playheadColor;

  final double contentWidth;
  final double padding;

  IsochronWaveformPainter({
    required this.waveform,
    required this.fragments,
    required this.playbackPosSeconds,
    required this.totalSeconds,
    required this.zoomLevel,
    this.activeFragmentIndex,
    required this.accentColor,
    required this.waveColor,
    required this.playheadColor,
    required this.contentWidth,
    required this.padding,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(padding, 0);

    _drawWaveform(canvas, Size(contentWidth, size.height));
    _drawFragments(canvas, Size(contentWidth, size.height));
    _drawPlayhead(canvas, Size(contentWidth, size.height));

    canvas.restore();
  }

  void _drawWaveform(Canvas canvas, Size size) {
    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = waveColor;

    final totalSamples = waveform.length;
    const double pixelStep = 1.0;

    for (double x = 0; x < size.width; x += pixelStep) {
      final sampleIdx = ((x / size.width) * totalSamples).toInt();
      if (sampleIdx >= 0 && sampleIdx < totalSamples) {
        final minY = _normalise(waveform.getPixelMin(sampleIdx), size.height);
        final maxY = _normalise(waveform.getPixelMax(sampleIdx), size.height);
        canvas.drawLine(Offset(x, minY), Offset(x, maxY), wavePaint);
      }
    }
  }

  void _drawFragments(Canvas canvas, Size size) {
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (final frag in fragments) {
      if (frag.realStart < 0) continue;

      final bool isActive = (frag.index == activeFragmentIndex);
      final bool isFlagged = frag.flags.isNotEmpty;
      final Color lineColor = isActive
          ? Colors.amberAccent
          : (isFlagged ? Colors.orangeAccent : accentColor);

      final paintLine = Paint()
        ..color = lineColor
        ..strokeWidth = isActive ? 3.0 : (isFlagged ? 2.5 : 2.0);

      final paintFill = Paint()
        ..color = lineColor.withValues(
          alpha: isActive ? 0.28 : (isFlagged ? 0.20 : 0.12),
        );

      final xStart = (frag.realStart / totalSeconds) * size.width;
      final xEnd = (frag.realEnd / totalSeconds) * size.width;

      canvas.drawRect(Rect.fromLTRB(xStart, 0, xEnd, size.height), paintFill);
      canvas.drawLine(
        Offset(xStart, 0),
        Offset(xStart, size.height),
        paintLine,
      );
      canvas.drawLine(Offset(xEnd, 0), Offset(xEnd, size.height), paintLine);

      // Ghost Marker: Subtle dashed line at autoStart if edited
      if (frag.status == FragmentStatus.edited &&
          frag.autoStart != null &&
          (frag.autoStart! - frag.realStart).abs() > 0.01) {
        final xGhost = (frag.autoStart! / totalSeconds) * size.width;
        final ghostPaint = Paint()
          ..color = accentColor.withValues(alpha: 0.45)
          ..strokeWidth = 1.5;

        // Draw vertical dashed line
        double curY = 0.0;
        const dashLen = 4.0;
        const gapLen = 4.0;
        while (curY < size.height) {
          canvas.drawLine(
            Offset(xGhost, curY),
            Offset(xGhost, (curY + dashLen).clamp(0.0, size.height)),
            ghostPaint,
          );
          curY += dashLen + gapLen;
        }
      }

      if (xEnd - xStart > 25) {
        textPainter.text = TextSpan(
          text: "${frag.index}",
          style: TextStyle(
            color: lineColor,
            fontWeight: FontWeight.bold,
            fontSize: 10,
          ),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(xStart + 4, 4));
      }
    }
  }

  void _drawPlayhead(Canvas canvas, Size size) {
    final x = (playbackPosSeconds / totalSeconds) * size.width;
    final paint = Paint()
      ..color = playheadColor
      ..strokeWidth = 2.0;

    canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);

    final pathHead = Path();
    pathHead.moveTo(x - 6, 0);
    pathHead.lineTo(x + 6, 0);
    pathHead.lineTo(x, 8);
    pathHead.close();
    canvas.drawPath(pathHead, Paint()..color = playheadColor);
  }

  double _normalise(int s, double height) {
    if (waveform.flags == 0) {
      final y = 32768 + (s).clamp(-32768.0, 32767.0).toDouble();
      return height - 1 - y * height / 65536;
    } else {
      final y = 128 + (s).clamp(-128.0, 127.0).toDouble();
      return height - 1 - y * height / 256;
    }
  }

  @override
  bool shouldRepaint(covariant IsochronWaveformPainter old) => true;
}
