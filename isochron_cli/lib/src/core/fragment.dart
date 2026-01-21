class Fragment {
  /// The sequential internal identifier (0, 1, 2...)
  /// Critical for array lookups and UI list ordering.
  final int index;

  /// The custom external identifier (e.g. "40001001")
  /// extracted from the text file.
  final String? id;

  /// The actual text content to be spoken
  final String text;

  /// Transliterated text if original text uses non-latin alphabet
  String? spokenText;

  // --- Anchor Timings ---
  double anchorStart = 0.0;
  double anchorEnd = 0.0;

  // --- Real Timings ---
  double realStart = 0.0;
  double realEnd = 0.0;

  Fragment({
    required this.index,
    required this.text,
    this.id,
    this.spokenText,
  });

  /// Helper to update real timing after alignment
  void setRealTiming({required double start, required double end}) {
    realStart = start;
    realEnd = end;
  }

  /// Helper to update anchor timing during synthesis
  void setAnchorTiming({required double start, required double end}) {
    anchorStart = start;
    anchorEnd = end;
  }

  Fragment copyWith({
    int? index,
    String? id,
    String? text,
    double? realStart,
    double? realEnd,
  }) {
    final f = Fragment(
      index: index ?? this.index,
      id: id ?? this.id,
      text: text ?? this.text,
    );
    f.realStart = realStart ?? this.realStart;
    f.realEnd = realEnd ?? this.realEnd;
    f.spokenText = spokenText;
    f.anchorStart = anchorStart;
    f.anchorEnd = anchorEnd;
    return f;
  }

  @override
  String toString() {
    // Helpful for debugging: shows ID if present, otherwise Index
    final label = id != null ? "ID:$id" : "#$index";
    return 'Fragment($label, text: "${text.substring(0, min(10, text.length))}...", $realStart - $realEnd)';
  }

  int min(int a, int b) => a < b ? a : b;
}
