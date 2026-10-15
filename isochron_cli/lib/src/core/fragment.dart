import 'dart:math' as math;

enum FragmentStatus {
  auto,
  edited,
  reviewed,
  legacy;

  static FragmentStatus fromString(String? value) {
    if (value == null) return FragmentStatus.legacy;
    return FragmentStatus.values.firstWhere(
      (v) => v.name == value.toLowerCase(),
      orElse: () => FragmentStatus.legacy,
    );
  }
}

class Fragment {
  /// The sequential internal identifier (0, 1, 2...)
  /// Critical for array lookups and UI list ordering.
  final int index;

  /// The custom external identifier (e.g. "40001001")
  /// extracted from the text file.
  final String? id;

  /// The actual text content to be spoken
  final String text;

  // --- Real Timings ---
  double realStart = 0.0;
  double realEnd = 0.0;

  // --- MMS Fields ---
  /// The original aligner recommendation (for ghost marker display).
  double? autoStart;

  /// Confidence score between 0.0 and 1.0.
  double? confidence;

  /// Diagnostic anomaly flags (e.g. not_at_pause, long_verse).
  List<String> flags = [];

  /// Lifecycle status: auto, edited, reviewed, or legacy.
  FragmentStatus status;

  /// Tokenizer and processing warnings (e.g. dropped digits, empty text).
  List<String> warnings = [];

  Fragment({
    required this.index,
    required this.text,
    this.id,
    this.autoStart,
    this.confidence,
    List<String>? flags,
    this.status = FragmentStatus.auto,
    List<String>? warnings,
  })  : flags = flags ?? [],
        warnings = warnings ?? [];

  /// Helper to update real timing after alignment
  void setRealTiming({required double start, required double end}) {
    realStart = start;
    realEnd = end;
  }

  Map<String, dynamic> toJson() => {
        'index': index,
        if (id != null) 'id': id,
        'text': text,
        'start': double.parse(realStart.toStringAsFixed(3)),
        'end': double.parse(realEnd.toStringAsFixed(3)),
        if (autoStart != null)
          'autoStart': double.parse(autoStart!.toStringAsFixed(3)),
        if (confidence != null)
          'confidence': double.parse(confidence!.toStringAsFixed(3)),
        if (flags.isNotEmpty) 'flags': flags,
        if (status != FragmentStatus.legacy) 'status': status.name,
        if (warnings.isNotEmpty) 'warnings': warnings,
      };

  factory Fragment.fromJson(Map<String, dynamic> json) {
    final f = Fragment(
      index: json['index'] as int,
      id: json['id']?.toString(),
      text: json['text'] as String? ?? '',
      autoStart: (json['autoStart'] as num?)?.toDouble(),
      confidence: (json['confidence'] as num?)?.toDouble(),
      flags: (json['flags'] as List?)?.map((e) => e.toString()).toList(),
      status: FragmentStatus.fromString(json['status']?.toString()),
      warnings: (json['warnings'] as List?)?.map((e) => e.toString()).toList(),
    );
    f.setRealTiming(
      start: (json['start'] as num?)?.toDouble() ?? 0.0,
      end: (json['end'] as num?)?.toDouble() ?? 0.0,
    );
    return f;
  }

  Fragment copyWith({
    int? index,
    String? id,
    String? text,
    double? realStart,
    double? realEnd,
    double? autoStart,
    double? confidence,
    List<String>? flags,
    FragmentStatus? status,
    List<String>? warnings,
  }) {
    final f = Fragment(
      index: index ?? this.index,
      id: id ?? this.id,
      text: text ?? this.text,
      autoStart: autoStart ?? this.autoStart,
      confidence: confidence ?? this.confidence,
      flags: flags ?? List.from(this.flags),
      status: status ?? this.status,
      warnings: warnings ?? List.from(this.warnings),
    );
    f.realStart = realStart ?? this.realStart;
    f.realEnd = realEnd ?? this.realEnd;
    return f;
  }

  @override
  String toString() {
    final label = id != null ? "ID:$id" : "#$index";
    return 'Fragment($label, text: "${text.substring(0, math.min(10, text.length))}...", $realStart - $realEnd)';
  }
}
