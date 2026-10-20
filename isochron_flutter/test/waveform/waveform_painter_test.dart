import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isochron_cli/isochron_cli.dart';
import 'package:isochron_flutter/ui/waveform/waveform_painter.dart';
import 'package:just_waveform/just_waveform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('IsochronWaveformPainter formatBadgeLabel produces fragment number only', () {
    expect(IsochronWaveformPainter.formatBadgeLabel(0), '#1');
    expect(IsochronWaveformPainter.formatBadgeLabel(4), '#5');
    expect(IsochronWaveformPainter.formatBadgeLabel(99), '#100');
  });

  test('IsochronWaveformPainter paints fragment number badge without id', () {
    final waveform = Waveform(
      version: 1,
      flags: 0,
      sampleRate: 44100,
      samplesPerPixel: 100,
      length: 100,
      data: List.filled(200, 0),
    );

    final fragments = [
      Fragment(
        index: 0,
        id: '40001001',
        text: 'First fragment',
      )..setRealTiming(start: 1.0, end: 5.0),
      Fragment(
        index: 1,
        id: '40001002',
        text: 'Second fragment',
      )..setRealTiming(start: 5.0, end: 9.0),
    ];

    final painter = IsochronWaveformPainter(
      waveform: waveform,
      fragments: fragments,
      playbackPosSeconds: 2.0,
      totalSeconds: 10.0,
      zoomLevel: 1.0,
      accentColor: Colors.blue,
      waveColor: Colors.grey,
      playheadColor: Colors.red,
      reviewedColor: Colors.green,
      warningColor: Colors.orange,
      destructiveColor: Colors.red,
      textColor: Colors.black,
      contentWidth: 1000.0,
      padding: 40.0,
    );

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    painter.paint(canvas, const Size(1000, 200));
    final picture = recorder.endRecording();
    expect(picture, isNotNull);
  });
}
