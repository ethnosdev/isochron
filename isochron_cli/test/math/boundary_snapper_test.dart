import 'dart:typed_data';

import 'package:isochron_cli/isochron_cli.dart';
import 'package:isochron_cli/src/math/boundary_snapper.dart';
import 'package:test/test.dart';

const int _sampleRate = 16000;

/// Silence then loud audio so onset detection fires in the ±250 ms window
/// around [realStart] 1.0 s (sample 16000).
Float64List _onsetAudio({int lengthSamples = 48000}) {
  final buf = Float64List(lengthSamples);
  for (var s = 16000; s < lengthSamples; s++) {
    buf[s] = 1.0;
  }
  return buf;
}

Fragment _frag(int index, double start, double end) {
  return Fragment(index: index, text: 'frag$index')
    ..setRealTiming(start: start, end: end);
}

Fragment _pinned(int index, double start, double end) {
  final f = Fragment(index: index, text: 'frag$index')
    ..setRealTiming(start: start, end: end);
  f.setPinnedTiming(start: start, end: end);
  return f;
}

void main() {
  group('BoundarySnapper', () {
    // Snapped start (s) follows first 100-sample energy crossing + shift-back—too
    // brittle for one exact expect; we use a band or baseline − offset instead.

    test('links previous fragment end to snapped start when snapOffset is 0',
        () {
      final audio = _onsetAudio();
      final frags = <Fragment>[
        _frag(0, 0.0, 1.0),
        _frag(1, 1.0, 2.0),
      ];

      BoundarySnapper.snap(frags, audio, _sampleRate, snapOffsetMs: 0);

      expect(frags[1].realStart, greaterThan(0.85));
      expect(frags[1].realStart, lessThan(0.9));
      expect(frags[0].realEnd, closeTo(frags[1].realStart, 1e-9));
    });

    test('subtracts snapOffsetMs from snapped start and links previous end',
        () {
      final audio = _onsetAudio();

      final baseline = <Fragment>[
        _frag(0, 0.0, 1.0),
        _frag(1, 1.0, 2.0),
      ];
      BoundarySnapper.snap(baseline, audio, _sampleRate, snapOffsetMs: 0);
      final baselineStart = baseline[1].realStart;

      final frags = <Fragment>[
        _frag(0, 0.0, 1.0),
        _frag(1, 1.0, 2.0),
      ];
      BoundarySnapper.snap(frags, audio, _sampleRate, snapOffsetMs: 250);

      expect(frags[1].realStart, closeTo(baselineStart - 0.25, 1e-6));
      expect(frags[0].realEnd, closeTo(frags[1].realStart, 1e-9));
    });

    test('does not move previous end when previous fragment is pinned', () {
      final audio = _onsetAudio();
      final frags = <Fragment>[
        _pinned(0, 0.0, 1.0),
        _frag(1, 1.0, 2.0),
      ];

      BoundarySnapper.snap(frags, audio, _sampleRate, snapOffsetMs: 0);

      expect(frags[0].realEnd, 1.0);
      expect(frags[1].realStart, greaterThan(0.85));
      expect(frags[1].realStart, lessThan(0.9));
    });

    test('clamps start at zero when snapOffset pulls before t=0', () {
      final audio = Float64List(48000);
      for (var s = 0; s < 48000; s++) {
        audio[s] = 1.0;
      }

      final frags = <Fragment>[_frag(0, 0.0, 0.5)];

      BoundarySnapper.snap(frags, audio, _sampleRate, snapOffsetMs: 500);

      expect(frags[0].realStart, 0.0);
    });
  });
}
