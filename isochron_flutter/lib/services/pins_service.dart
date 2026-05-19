import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:isochron_cli/isochron_cli.dart';
import 'package:path/path.dart' as p;

/// Handles persistence of pinned fragment timings to a JSON sidecar file.
///
/// The sidecar sits alongside the alignment JSON:
///   alignments/foo.json  →  alignments/foo-pins.json
///
/// Format:
/// ```json
/// {
///   "0": { "start": 1.234, "end": 5.678 },
///   "3": { "start": 12.0,  "end": 15.5  }
/// }
/// ```
class PinsService {
  /// Returns the sidecar pins path for a given alignment JSON path.
  static String pinsPath(String alignmentJsonPath) {
    final dir = p.dirname(alignmentJsonPath);
    final stem = p.basenameWithoutExtension(alignmentJsonPath);
    return p.join(dir, '$stem-pins.json');
  }

  /// Saves pinned fragments to the sidecar file alongside [alignmentJsonPath].
  ///
  /// If no fragments are pinned the file is deleted (or left absent), keeping
  /// the project directory clean.
  Future<void> save(String alignmentJsonPath, List<Fragment> fragments) async {
    final path = pinsPath(alignmentJsonPath);
    final pinned = fragments.where((f) => f.isPinned).toList();

    if (pinned.isEmpty) {
      final file = File(path);
      if (await file.exists()) await file.delete();
      return;
    }

    final file = File(path);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }

    final map = <String, dynamic>{
      for (final f in pinned)
        '${f.index}': {
          'start': double.parse(f.pinnedStart!.toStringAsFixed(3)),
          'end': double.parse(f.pinnedEnd!.toStringAsFixed(3)),
        },
    };

    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(map));
    debugPrint('[PIN] Saved pins to $path');
  }

  /// Reads the sidecar file and applies pinned timings to [fragments] in place.
  ///
  /// Silently no-ops if the file does not exist. Logs and swallows parse
  /// errors so a corrupt sidecar never blocks opening a file.
  Future<void> load(String alignmentJsonPath, List<Fragment> fragments) async {
    final file = File(pinsPath(alignmentJsonPath));
    if (!await file.exists()) return;

    try {
      final Map<String, dynamic> pinsMap = jsonDecode(
        await file.readAsString(),
      );
      for (final entry in pinsMap.entries) {
        final idx = int.tryParse(entry.key);
        if (idx == null) continue;
        final fragIdx = fragments.indexWhere((f) => f.index == idx);
        if (fragIdx == -1) continue;
        final v = entry.value as Map<String, dynamic>;
        fragments[fragIdx].setPinnedTiming(
          start: (v['start'] as num).toDouble(),
          end: (v['end'] as num).toDouble(),
        );
      }
      debugPrint('[PIN] Restored pins from ${file.path}');
    } catch (e) {
      debugPrint('[PIN] Failed to load pins: $e');
    }
  }
}
