import 'package:path/path.dart' as p;
import 'natural_sort.dart';

enum PairingStrategy {
  smartAuto,
  exactStem,
  numericTokens,
  listOrder,
}

enum TrackNameRule {
  audioStem,
  textStem,
}

class PairedRow {
  String? audioPath;
  String? textPath;
  String name;

  PairedRow({
    this.audioPath,
    this.textPath,
    required this.name,
  });

  bool get isComplete => audioPath != null && textPath != null;
  bool get isAudioOnly => audioPath != null && textPath == null;
  bool get isTextOnly => audioPath == null && textPath != null;

  PairedRow clone() => PairedRow(
        audioPath: audioPath,
        textPath: textPath,
        name: name,
      );
}

class MediaPairingEngine {
  /// Extracts all integer numbers found in a filename.
  static List<int> extractNumbers(String path) {
    final stem = p.basenameWithoutExtension(path);
    final matches = RegExp(r'\d+').allMatches(stem);
    return matches.map((m) => int.parse(m.group(0)!)).toList();
  }

  /// Extracts the normalized stem (lowercase, trimmed).
  static String extractStem(String path) {
    return p.basenameWithoutExtension(path).toLowerCase().trim();
  }

  /// Generates the default track name for a pair based on the naming rule.
  static String deriveTrackName({
    String? audioPath,
    String? textPath,
    TrackNameRule rule = TrackNameRule.audioStem,
  }) {
    if (rule == TrackNameRule.audioStem && audioPath != null) {
      return p.basenameWithoutExtension(audioPath);
    }
    if (rule == TrackNameRule.textStem && textPath != null) {
      return p.basenameWithoutExtension(textPath);
    }
    if (audioPath != null) {
      return p.basenameWithoutExtension(audioPath);
    }
    if (textPath != null) {
      return p.basenameWithoutExtension(textPath);
    }
    return 'Untitled Track';
  }

  /// Computes pairings for lists of audio and text files based on the given strategy.
  static List<PairedRow> computePairings({
    required List<String> audioFiles,
    required List<String> textFiles,
    PairingStrategy strategy = PairingStrategy.smartAuto,
    TrackNameRule nameRule = TrackNameRule.audioStem,
  }) {
    final sortedAudio = List<String>.from(audioFiles);
    final sortedText = List<String>.from(textFiles);
    naturalSort(sortedAudio);
    naturalSort(sortedText);

    switch (strategy) {
      case PairingStrategy.listOrder:
        return _pairByListOrder(sortedAudio, sortedText, nameRule);
      case PairingStrategy.exactStem:
        return _pairByExactStem(sortedAudio, sortedText, nameRule);
      case PairingStrategy.numericTokens:
        return _pairByNumericTokens(sortedAudio, sortedText, nameRule);
      case PairingStrategy.smartAuto:
        return _pairSmartAuto(sortedAudio, sortedText, nameRule);
    }
  }

  static List<PairedRow> _pairByListOrder(
    List<String> sortedAudio,
    List<String> sortedText,
    TrackNameRule nameRule,
  ) {
    final rows = <PairedRow>[];
    final maxLen = sortedAudio.length > sortedText.length
        ? sortedAudio.length
        : sortedText.length;

    for (int i = 0; i < maxLen; i++) {
      final audio = i < sortedAudio.length ? sortedAudio[i] : null;
      final text = i < sortedText.length ? sortedText[i] : null;
      rows.add(
        PairedRow(
          audioPath: audio,
          textPath: text,
          name: deriveTrackName(
            audioPath: audio,
            textPath: text,
            rule: nameRule,
          ),
        ),
      );
    }
    return rows;
  }

  static List<PairedRow> _pairByExactStem(
    List<String> sortedAudio,
    List<String> sortedText,
    TrackNameRule nameRule,
  ) {
    final rows = <PairedRow>[];
    final remainingAudio = List<String>.from(sortedAudio);
    final remainingText = List<String>.from(sortedText);

    // 1. Match exact stems
    for (int i = remainingAudio.length - 1; i >= 0; i--) {
      final a = remainingAudio[i];
      final aStem = extractStem(a);
      final tIndex = remainingText.indexWhere((t) => extractStem(t) == aStem);
      if (tIndex != -1) {
        final t = remainingText.removeAt(tIndex);
        remainingAudio.removeAt(i);
        rows.add(
          PairedRow(
            audioPath: a,
            textPath: t,
            name: deriveTrackName(audioPath: a, textPath: t, rule: nameRule),
          ),
        );
      }
    }

    // 2. Append remaining audio-only
    for (final a in remainingAudio) {
      rows.add(
        PairedRow(
          audioPath: a,
          textPath: null,
          name: deriveTrackName(audioPath: a, rule: nameRule),
        ),
      );
    }

    // 3. Append remaining text-only
    for (final t in remainingText) {
      rows.add(
        PairedRow(
          audioPath: null,
          textPath: t,
          name: deriveTrackName(textPath: t, rule: nameRule),
        ),
      );
    }

    _sortRows(rows);
    return rows;
  }

  static List<PairedRow> _pairByNumericTokens(
    List<String> sortedAudio,
    List<String> sortedText,
    TrackNameRule nameRule,
  ) {
    final rows = <PairedRow>[];
    final remainingAudio = List<String>.from(sortedAudio);
    final remainingText = List<String>.from(sortedText);

    bool numbersMatch(List<int> aNums, List<int> tNums) {
      if (aNums.isEmpty || tNums.isEmpty) return false;
      // Exact sequence match
      if (aNums.length == tNums.length) {
        bool allMatch = true;
        for (int i = 0; i < aNums.length; i++) {
          if (aNums[i] != tNums[i]) {
            allMatch = false;
            break;
          }
        }
        if (allMatch) return true;
      }
      // If either has single number (e.g. chapter number), check if last numbers match
      if (aNums.last == tNums.last) return true;
      return false;
    }

    for (int i = remainingAudio.length - 1; i >= 0; i--) {
      final a = remainingAudio[i];
      final aNums = extractNumbers(a);
      if (aNums.isEmpty) continue;

      final tIndex = remainingText.indexWhere((t) {
        final tNums = extractNumbers(t);
        return numbersMatch(aNums, tNums);
      });

      if (tIndex != -1) {
        final t = remainingText.removeAt(tIndex);
        remainingAudio.removeAt(i);
        rows.add(
          PairedRow(
            audioPath: a,
            textPath: t,
            name: deriveTrackName(audioPath: a, textPath: t, rule: nameRule),
          ),
        );
      }
    }

    for (final a in remainingAudio) {
      rows.add(
        PairedRow(
          audioPath: a,
          textPath: null,
          name: deriveTrackName(audioPath: a, rule: nameRule),
        ),
      );
    }

    for (final t in remainingText) {
      rows.add(
        PairedRow(
          audioPath: null,
          textPath: t,
          name: deriveTrackName(textPath: t, rule: nameRule),
        ),
      );
    }

    _sortRows(rows);
    return rows;
  }

  static List<PairedRow> _pairSmartAuto(
    List<String> sortedAudio,
    List<String> sortedText,
    TrackNameRule nameRule,
  ) {
    final rows = <PairedRow>[];
    final remainingAudio = List<String>.from(sortedAudio);
    final remainingText = List<String>.from(sortedText);

    // Pass 1: Exact stem match
    for (int i = remainingAudio.length - 1; i >= 0; i--) {
      final a = remainingAudio[i];
      final aStem = extractStem(a);
      final tIndex = remainingText.indexWhere((t) => extractStem(t) == aStem);
      if (tIndex != -1) {
        final t = remainingText.removeAt(tIndex);
        remainingAudio.removeAt(i);
        rows.add(
          PairedRow(
            audioPath: a,
            textPath: t,
            name: deriveTrackName(audioPath: a, textPath: t, rule: nameRule),
          ),
        );
      }
    }

    // Pass 2: Numeric token match for remainder
    bool numbersMatch(List<int> aNums, List<int> tNums) {
      if (aNums.isEmpty || tNums.isEmpty) return false;
      if (aNums.length == tNums.length) {
        bool allMatch = true;
        for (int i = 0; i < aNums.length; i++) {
          if (aNums[i] != tNums[i]) {
            allMatch = false;
            break;
          }
        }
        if (allMatch) return true;
      }
      if (aNums.last == tNums.last) return true;
      return false;
    }

    for (int i = remainingAudio.length - 1; i >= 0; i--) {
      final a = remainingAudio[i];
      final aNums = extractNumbers(a);
      if (aNums.isEmpty) continue;

      final tIndex = remainingText.indexWhere((t) {
        final tNums = extractNumbers(t);
        return numbersMatch(aNums, tNums);
      });

      if (tIndex != -1) {
        final t = remainingText.removeAt(tIndex);
        remainingAudio.removeAt(i);
        rows.add(
          PairedRow(
            audioPath: a,
            textPath: t,
            name: deriveTrackName(audioPath: a, textPath: t, rule: nameRule),
          ),
        );
      }
    }

    // Pass 3: If counts of remaining audio and text match, pair in natural list order
    if (remainingAudio.isNotEmpty &&
        remainingAudio.length == remainingText.length) {
      naturalSort(remainingAudio);
      naturalSort(remainingText);
      for (int i = 0; i < remainingAudio.length; i++) {
        final a = remainingAudio[i];
        final t = remainingText[i];
        rows.add(
          PairedRow(
            audioPath: a,
            textPath: t,
            name: deriveTrackName(audioPath: a, textPath: t, rule: nameRule),
          ),
        );
      }
      remainingAudio.clear();
      remainingText.clear();
    }

    // Pass 4: Append any lingering audio-only
    for (final a in remainingAudio) {
      rows.add(
        PairedRow(
          audioPath: a,
          textPath: null,
          name: deriveTrackName(audioPath: a, rule: nameRule),
        ),
      );
    }

    // Pass 5: Append any lingering text-only
    for (final t in remainingText) {
      rows.add(
        PairedRow(
          audioPath: null,
          textPath: t,
          name: deriveTrackName(textPath: t, rule: nameRule),
        ),
      );
    }

    _sortRows(rows);
    return rows;
  }

  static void _sortRows(List<PairedRow> rows) {
    final names = rows.map((r) => r.name).toList();
    naturalSort(names);

    final map = <String, List<PairedRow>>{};
    for (final r in rows) {
      map.putIfAbsent(r.name, () => []).add(r);
    }

    rows.clear();
    for (final n in names) {
      if (map[n] != null && map[n]!.isNotEmpty) {
        rows.add(map[n]!.removeAt(0));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // INTERACTIVE ADJUSTMENTS
  // ---------------------------------------------------------------------------

  /// Inserts a gap (blank cell) in either the audio or text column at [index],
  /// shifting subsequent items down to the next row.
  static void insertGap(List<PairedRow> rows, int index, {required bool isText}) {
    if (index < 0 || index >= rows.length) return;

    if (isText) {
      // Shift text downwards starting from index
      String? carryText = rows[index].textPath;
      rows[index].textPath = null;

      for (int i = index + 1; i < rows.length; i++) {
        final temp = rows[i].textPath;
        rows[i].textPath = carryText;
        carryText = temp;
      }
      if (carryText != null) {
        rows.add(
          PairedRow(
            audioPath: null,
            textPath: carryText,
            name: deriveTrackName(textPath: carryText),
          ),
        );
      }
    } else {
      // Shift audio downwards starting from index
      String? carryAudio = rows[index].audioPath;
      rows[index].audioPath = null;

      for (int i = index + 1; i < rows.length; i++) {
        final temp = rows[i].audioPath;
        rows[i].audioPath = carryAudio;
        carryAudio = temp;
      }
      if (carryAudio != null) {
        rows.add(
          PairedRow(
            audioPath: carryAudio,
            textPath: null,
            name: deriveTrackName(audioPath: carryAudio),
          ),
        );
      }
    }
    _cleanEmptyRows(rows);
  }

  /// Shifts an item in the given column up by 1 row (swapping with the row above or moving into an empty slot).
  static void shiftUp(List<PairedRow> rows, int index, {required bool isText}) {
    if (index <= 0 || index >= rows.length) return;

    if (isText) {
      final current = rows[index].textPath;
      rows[index].textPath = rows[index - 1].textPath;
      rows[index - 1].textPath = current;
    } else {
      final current = rows[index].audioPath;
      rows[index].audioPath = rows[index - 1].audioPath;
      rows[index - 1].audioPath = current;
    }
    _cleanEmptyRows(rows);
  }

  /// Shifts an item in the given column down by 1 row (swapping with the row below or moving into an empty slot).
  static void shiftDown(List<PairedRow> rows, int index, {required bool isText}) {
    if (index < 0 || index >= rows.length - 1) return;

    if (isText) {
      final current = rows[index].textPath;
      rows[index].textPath = rows[index + 1].textPath;
      rows[index + 1].textPath = current;
    } else {
      final current = rows[index].audioPath;
      rows[index].audioPath = rows[index + 1].audioPath;
      rows[index + 1].audioPath = current;
    }
    _cleanEmptyRows(rows);
  }

  /// Reorders an item in either the audio or text column from [oldIndex] to [newIndex].
  static void reorderColumn(
    List<PairedRow> rows,
    int oldIndex,
    int newIndex, {
    required bool isText,
  }) {
    if (oldIndex < 0 || oldIndex >= rows.length) return;
    if (newIndex < 0 || newIndex >= rows.length) return;
    if (oldIndex == newIndex) return;

    if (isText) {
      final val = rows[oldIndex].textPath;
      rows[oldIndex].textPath = null;
      // Pull and insert
      if (oldIndex < newIndex) {
        for (int i = oldIndex; i < newIndex; i++) {
          rows[i].textPath = rows[i + 1].textPath;
        }
      } else {
        for (int i = oldIndex; i > newIndex; i--) {
          rows[i].textPath = rows[i - 1].textPath;
        }
      }
      rows[newIndex].textPath = val;
    } else {
      final val = rows[oldIndex].audioPath;
      rows[oldIndex].audioPath = null;
      if (oldIndex < newIndex) {
        for (int i = oldIndex; i < newIndex; i++) {
          rows[i].audioPath = rows[i + 1].audioPath;
        }
      } else {
        for (int i = oldIndex; i > newIndex; i--) {
          rows[i].audioPath = rows[i - 1].audioPath;
        }
      }
      rows[newIndex].audioPath = val;
    }
    _cleanEmptyRows(rows);
  }

  /// Removes empty rows where both audioPath and textPath are null.
  static void _cleanEmptyRows(List<PairedRow> rows) {
    rows.removeWhere((r) => r.audioPath == null && r.textPath == null);
  }

  /// Applies the naming rule across all rows.
  static void applyNamingRule(List<PairedRow> rows, TrackNameRule rule) {
    for (final r in rows) {
      r.name = deriveTrackName(
        audioPath: r.audioPath,
        textPath: r.textPath,
        rule: rule,
      );
    }
  }
}
