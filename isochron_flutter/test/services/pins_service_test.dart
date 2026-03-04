import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isochron_cli/isochron_cli.dart';
import 'package:isochron_flutter/services/pins_service.dart';
import 'package:path/path.dart' as p;

/// Builds a Fragment with real timing set.
Fragment makeFragment(int index, double start, double end) {
  return Fragment(index: index, text: 'text $index')
    ..setRealTiming(start: start, end: end);
}

void main() {
  late Directory tempDir;
  late String alignmentPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pins_service_test_');
    alignmentPath = p.join(tempDir.path, 'foo.json');
    File(alignmentPath).writeAsStringSync('[]');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  // ---------------------------------------------------------------------------
  group('PinsService.pinsPath', () {
    test('derives correct sidecar path', () {
      final result = PinsService.pinsPath('/project/alignments/foo.json');
      expect(result, '/project/alignments/foo-pins.json');
    });

    test('works with nested paths', () {
      expect(PinsService.pinsPath('/a/b/c/bar.json'), '/a/b/c/bar-pins.json');
    });
  });

  // ---------------------------------------------------------------------------
  group('PinsService.save', () {
    test(
      'creates pins file with correct JSON when a fragment is pinned',
      () async {
        final service = PinsService();
        final frags = [makeFragment(0, 1.0, 3.0), makeFragment(1, 3.0, 7.5)];
        frags[0].setPinnedTiming(start: 1.0, end: 3.0);

        await service.save(alignmentPath, frags);

        final pinsFile = File(PinsService.pinsPath(alignmentPath));
        expect(await pinsFile.exists(), isTrue);

        final map = jsonDecode(await pinsFile.readAsString()) as Map;
        expect(map.keys.toList(), ['0']);
        expect((map['0']['start'] as num).toDouble(), 1.0);
        expect((map['0']['end'] as num).toDouble(), 3.0);
      },
    );

    test('writes all pinned fragments', () async {
      final service = PinsService();
      final frags = [
        makeFragment(0, 0.0, 2.0),
        makeFragment(1, 2.0, 5.0),
        makeFragment(2, 5.0, 9.0),
      ];
      frags[0].setPinnedTiming(start: 0.0, end: 2.0);
      frags[2].setPinnedTiming(start: 5.0, end: 9.0);

      await service.save(alignmentPath, frags);

      final map =
          jsonDecode(
                await File(PinsService.pinsPath(alignmentPath)).readAsString(),
              )
              as Map;
      expect(map.keys.toSet(), {'0', '2'});
    });

    test('deletes existing pins file when no fragments are pinned', () async {
      final service = PinsService();
      File(PinsService.pinsPath(alignmentPath)).writeAsStringSync('{}');

      await service.save(alignmentPath, [makeFragment(0, 0.0, 2.0)]);

      expect(await File(PinsService.pinsPath(alignmentPath)).exists(), isFalse);
    });

    test('does not throw when no pins and no sidecar exists', () async {
      await expectLater(
        PinsService().save(alignmentPath, [makeFragment(0, 0.0, 2.0)]),
        completes,
      );
      expect(await File(PinsService.pinsPath(alignmentPath)).exists(), isFalse);
    });

    test('rounds timing values to 3 decimal places', () async {
      final frags = [makeFragment(0, 0.0, 9.0)];
      frags[0].setPinnedTiming(start: 1.23456789, end: 4.56789);

      await PinsService().save(alignmentPath, frags);

      final map =
          jsonDecode(
                await File(PinsService.pinsPath(alignmentPath)).readAsString(),
              )
              as Map;
      expect(map['0']['start'], 1.235);
      expect(map['0']['end'], 4.568);
    });
  });

  // ---------------------------------------------------------------------------
  group('PinsService.load', () {
    test('applies pinned timings to matching fragments', () async {
      File(PinsService.pinsPath(alignmentPath)).writeAsStringSync(
        jsonEncode({
          '1': {'start': 3.0, 'end': 7.5},
        }),
      );

      final frags = [makeFragment(0, 0.0, 3.0), makeFragment(1, 3.0, 7.5)];
      await PinsService().load(alignmentPath, frags);

      expect(frags[0].isPinned, isFalse);
      expect(frags[1].isPinned, isTrue);
      expect(frags[1].pinnedStart, 3.0);
      expect(frags[1].pinnedEnd, 7.5);
    });

    test('is a no-op when sidecar does not exist', () async {
      final frags = [makeFragment(0, 0.0, 2.0)];
      await expectLater(PinsService().load(alignmentPath, frags), completes);
      expect(frags[0].isPinned, isFalse);
    });

    test('handles corrupt JSON without throwing', () async {
      File(PinsService.pinsPath(alignmentPath)).writeAsStringSync('NOT JSON');

      final frags = [makeFragment(0, 0.0, 2.0)];
      await expectLater(PinsService().load(alignmentPath, frags), completes);
      expect(frags[0].isPinned, isFalse);
    });

    test('skips unknown fragment indices gracefully', () async {
      File(PinsService.pinsPath(alignmentPath)).writeAsStringSync(
        jsonEncode({
          '99': {'start': 1.0, 'end': 2.0},
        }),
      );

      final frags = [makeFragment(0, 0.0, 2.0)];
      await expectLater(PinsService().load(alignmentPath, frags), completes);
      expect(frags[0].isPinned, isFalse);
    });

    test('round-trips: save then load restores all pins', () async {
      final service = PinsService();
      final orig = [
        makeFragment(0, 1.0, 3.5),
        makeFragment(1, 3.5, 8.0),
        makeFragment(2, 8.0, 12.0),
      ];
      orig[0].setPinnedTiming(start: 1.0, end: 3.5);
      orig[2].setPinnedTiming(start: 8.0, end: 12.0);
      await service.save(alignmentPath, orig);

      // Fresh unpinned list
      final restored = [
        makeFragment(0, 1.0, 3.5),
        makeFragment(1, 3.5, 8.0),
        makeFragment(2, 8.0, 12.0),
      ];
      await service.load(alignmentPath, restored);

      expect(restored[0].isPinned, isTrue);
      expect(restored[0].pinnedStart, 1.0);
      expect(restored[0].pinnedEnd, 3.5);
      expect(restored[1].isPinned, isFalse);
      expect(restored[2].isPinned, isTrue);
      expect(restored[2].pinnedStart, 8.0);
      expect(restored[2].pinnedEnd, 12.0);
    });
  });
}
