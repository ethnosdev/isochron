import 'package:flutter/material.dart';
import 'package:isochron_cli/isochron_cli.dart';
import 'package:just_waveform/just_waveform.dart';

class IsochronWaveformPainter extends CustomPainter {
  final Waveform waveform;
  final List<Fragment> fragments;
  final double playbackPosSeconds;
  final double totalSeconds;
  final double zoomLevel;

  // --- Dynamic Theme Colors ---
  final Color accentColor;
  final Color waveColor;
  final Color playheadColor;
  final Color reviewedColor;
  final Color warningColor;
  final Color destructiveColor;
  final Color textColor;

  // Selection & Hover State
  final int? selectedFragmentIndex;
  final int? hoveredFragmentIndex;
  final double? hoveredBoundaryTime;

  final double contentWidth;
  final double padding;

  IsochronWaveformPainter({
    required this.waveform,
    required this.fragments,
    required this.playbackPosSeconds,
    required this.totalSeconds,
    required this.zoomLevel,
    required this.accentColor,
    required this.waveColor,
    required this.playheadColor,
    required this.reviewedColor,
    required this.warningColor,
    required this.destructiveColor,
    required this.textColor,
    this.selectedFragmentIndex,
    this.hoveredFragmentIndex,
    this.hoveredBoundaryTime,
    required this.contentWidth,
    required this.padding,
  });

  static const double rulerHeight = 22.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(padding, 0);

    final contentSize = Size(contentWidth, size.height);
    _drawTimelineRuler(canvas, contentSize);
    _drawWaveform(canvas, contentSize);
    _drawFragments(canvas, contentSize);
    _drawPlayhead(canvas, contentSize);

    canvas.restore();
  }

  void _drawTimelineRuler(Canvas canvas, Size size) {
    if (totalSeconds <= 0) return;

    // Header strip
    final rulerPaint = Paint()
      ..color = waveColor.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, rulerHeight), rulerPaint);

    // 1px bottom border
    final borderPaint = Paint()
      ..color = waveColor.withValues(alpha: 0.25)
      ..strokeWidth = 1.0;
    canvas.drawLine(
      const Offset(0, rulerHeight),
      Offset(size.width, rulerHeight),
      borderPaint,
    );

    final pixelsPerSecond = size.width / totalSeconds;
    double majorInterval;
    double minorInterval;

    if (pixelsPerSecond > 150) {
      majorInterval = 1.0;
      minorInterval = 0.2;
    } else if (pixelsPerSecond > 40) {
      majorInterval = 5.0;
      minorInterval = 1.0;
    } else if (pixelsPerSecond > 10) {
      majorInterval = 15.0;
      minorInterval = 5.0;
    } else {
      majorInterval = 60.0;
      minorInterval = 15.0;
    }

    final tickPaint = Paint()
      ..color = textColor.withValues(alpha: 0.4)
      ..strokeWidth = 1.0;
    final majorTickPaint = Paint()
      ..color = textColor.withValues(alpha: 0.7)
      ..strokeWidth = 1.0;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    // Minor ticks
    if (minorInterval > 0) {
      double t = 0.0;
      while (t <= totalSeconds) {
        final x = (t / totalSeconds) * size.width;
        canvas.drawLine(
          Offset(x, rulerHeight - 4),
          Offset(x, rulerHeight),
          tickPaint,
        );
        t += minorInterval;
      }
    }

    // Major ticks & labels
    double t = 0.0;
    while (t <= totalSeconds) {
      final x = (t / totalSeconds) * size.width;
      canvas.drawLine(
        Offset(x, rulerHeight - 8),
        Offset(x, rulerHeight),
        majorTickPaint,
      );

      final int totalSecInt = t.toInt();
      final minutes = (totalSecInt ~/ 60).toString().padLeft(2, '0');
      final seconds = (totalSecInt % 60).toString().padLeft(2, '0');

      String labelStr;
      if (pixelsPerSecond > 150) {
        final decimal = ((t - totalSecInt) * 10).toInt();
        labelStr = "$minutes:$seconds.$decimal";
      } else {
        labelStr = "$minutes:$seconds";
      }

      textPainter.text = TextSpan(
        text: labelStr,
        style: TextStyle(
          color: textColor.withValues(alpha: 0.65),
          fontSize: 9.0,
          fontWeight: FontWeight.w500,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x + 3, 2));

      t += majorInterval;
    }
  }

  void _drawWaveform(Canvas canvas, Size size) {
    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = waveColor;

    final totalSamples = waveform.length;
    const double pixelStep = 1.0;
    final waveHeight = size.height - rulerHeight;

    for (double x = 0; x < size.width; x += pixelStep) {
      final sampleIdx = ((x / size.width) * totalSamples).toInt();
      if (sampleIdx >= 0 && sampleIdx < totalSamples) {
        final minY =
            rulerHeight +
            _normalise(waveform.getPixelMin(sampleIdx), waveHeight);
        final maxY =
            rulerHeight +
            _normalise(waveform.getPixelMax(sampleIdx), waveHeight);
        canvas.drawLine(Offset(x, minY), Offset(x, maxY), wavePaint);
      }
    }
  }

  void _drawFragments(Canvas canvas, Size size) {
    if (totalSeconds <= 0) return;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (final frag in fragments) {
      if (frag.realStart < 0) continue;

      final xStart = (frag.realStart / totalSeconds) * size.width;
      final xEnd = (frag.realEnd / totalSeconds) * size.width;

      // Determine Region Color
      Color regionColor;
      if (frag.flags.isNotEmpty || frag.warnings.isNotEmpty) {
        regionColor = destructiveColor;
      } else if (frag.status == FragmentStatus.reviewed) {
        regionColor = reviewedColor;
      } else if (frag.status == FragmentStatus.edited) {
        regionColor = warningColor;
      } else {
        regionColor = accentColor;
      }

      final isSelected = frag.index == selectedFragmentIndex;
      final isHovered = frag.index == hoveredFragmentIndex;

      // Fill Alpha
      double fillAlpha = 0.12;
      if (isSelected) {
        fillAlpha = 0.24;
      } else if (isHovered) {
        fillAlpha = 0.18;
      }

      final fillPaint = Paint()
        ..color = regionColor.withValues(alpha: fillAlpha);
      canvas.drawRect(
        Rect.fromLTRB(xStart, rulerHeight, xEnd, size.height),
        fillPaint,
      );

      // Top Highlight Bar for Selected Fragment
      if (isSelected) {
        final highlightPaint = Paint()
          ..color = regionColor
          ..style = PaintingStyle.fill;
        canvas.drawRect(
          Rect.fromLTWH(xStart, rulerHeight, xEnd - xStart, 2.0),
          highlightPaint,
        );
      }

      // Boundaries
      final boundaryPaint = Paint()
        ..color = regionColor
        ..strokeWidth = 2.0;
      canvas.drawLine(
        Offset(xStart, rulerHeight),
        Offset(xStart, size.height),
        boundaryPaint,
      );
      canvas.drawLine(
        Offset(xEnd, rulerHeight),
        Offset(xEnd, size.height),
        boundaryPaint,
      );

      // Hovered Boundary Handle Glow & Circular Midpoint Grab Handle
      if (hoveredBoundaryTime != null) {
        final midY = rulerHeight + (size.height - rulerHeight) / 2;

        if ((frag.realStart - hoveredBoundaryTime!).abs() < 0.001) {
          final glowPaint = Paint()
            ..color = regionColor
            ..strokeWidth = 3.5;
          canvas.drawLine(
            Offset(xStart, rulerHeight),
            Offset(xStart, size.height),
            glowPaint,
          );
          canvas.drawCircle(Offset(xStart, midY), 5.0, glowPaint);
          canvas.drawCircle(
            Offset(xStart, midY),
            2.5,
            Paint()..color = Colors.white,
          );
        }

        if ((frag.realEnd - hoveredBoundaryTime!).abs() < 0.001) {
          final glowPaint = Paint()
            ..color = regionColor
            ..strokeWidth = 3.5;
          canvas.drawLine(
            Offset(xEnd, rulerHeight),
            Offset(xEnd, size.height),
            glowPaint,
          );
          canvas.drawCircle(Offset(xEnd, midY), 5.0, glowPaint);
          canvas.drawCircle(
            Offset(xEnd, midY),
            2.5,
            Paint()..color = Colors.white,
          );
        }
      }

      // Ghost Marker: Subtle dashed line at autoStart if edited
      if (frag.status == FragmentStatus.edited &&
          frag.autoStart != null &&
          (frag.autoStart! - frag.realStart).abs() > 0.01) {
        final xGhost = (frag.autoStart! / totalSeconds) * size.width;
        final ghostPaint = Paint()
          ..color = regionColor.withValues(alpha: 0.45)
          ..strokeWidth = 1.5;

        double curY = rulerHeight;
        const dashLen = 4.0;
        const gapLen = 4.0;
        while (curY < size.height) {
          canvas.drawLine(
            Offset(xGhost, curY),
            Offset(xGhost, (curY + dashLen).clamp(rulerHeight, size.height)),
            ghostPaint,
          );
          curY += dashLen + gapLen;
        }
      }

      // Label Badge
      if (xEnd - xStart > 24) {
        final labelText =
            (xEnd - xStart > 65 && frag.id != null && frag.id!.isNotEmpty)
                ? "#${frag.index + 1} • ${frag.id}"
                : "#${frag.index + 1}";

        textPainter.text = TextSpan(
          text: labelText,
          style: TextStyle(
            color: regionColor,
            fontWeight: FontWeight.bold,
            fontSize: 9.5,
          ),
        );
        textPainter.layout();

        final badgeRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            xStart + 4,
            rulerHeight + 4,
            textPainter.width + 6,
            textPainter.height + 2,
          ),
          const Radius.circular(3),
        );
        canvas.drawRRect(
          badgeRect,
          Paint()..color = regionColor.withValues(alpha: 0.16),
        );
        textPainter.paint(canvas, Offset(xStart + 7, rulerHeight + 5));
      }
    }
  }

  void _drawPlayhead(Canvas canvas, Size size) {
    if (totalSeconds <= 0) return;
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
  bool shouldRepaint(covariant IsochronWaveformPainter old) {
    return old.playbackPosSeconds != playbackPosSeconds ||
        old.zoomLevel != zoomLevel ||
        old.fragments != fragments ||
        old.selectedFragmentIndex != selectedFragmentIndex ||
        old.hoveredFragmentIndex != hoveredFragmentIndex ||
        old.hoveredBoundaryTime != hoveredBoundaryTime ||
        old.totalSeconds != totalSeconds ||
        old.contentWidth != contentWidth ||
        old.accentColor != accentColor ||
        old.reviewedColor != reviewedColor ||
        old.warningColor != warningColor ||
        old.destructiveColor != destructiveColor ||
        old.playheadColor != playheadColor;
  }
}
