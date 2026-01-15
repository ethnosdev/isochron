class Fragment {
  /// The sequential identifier (useful for debugging and ordering)
  final int index;

  /// The actual text content to be spoken
  final String text;

  /// Transliterated text if original text uses non-latin alphabet
  String? spokenText;

  // --- Anchor Timings (The "Map") ---
  // When this fragment starts/ends in the synthetic (TTS) audio.
  // Calculated in Phase 2.
  double anchorStart = 0.0;
  double anchorEnd = 0.0;

  // --- Real Timings (The "Destination") ---
  // When this fragment starts/ends in the user's recording.
  // Calculated in Phase 5 (after DTW).
  double realStart = 0.0;
  double realEnd = 0.0;

  Fragment({
    required this.index,
    required this.text,
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

  @override
  String toString() {
    return 'Fragment(id: $index, text: "$text", real: $realStart - $realEnd)';
  }
}
