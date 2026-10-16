# isochron_cli

A high-performance, pure-Dart forced aligner engine powered by Meta's **MMS-300M** neural acoustic model and ONNX Runtime.

`isochron_cli` aligns spoken audio recordings with text transcripts with sub-10 millisecond accuracy across **1,130+ languages**, running completely offline and locally on macOS.

---

## Features

- **MMS-300M Wav2Vec2 + CTC Engine:** Native ONNX Runtime FFI integration running dynamically quantized int8 weights on CPU SIMD.
- **Universal Multilingual Support:** Romanization and normalization for 1,130+ languages via `uroman`.
- **Acoustic Pause Snapping:** 10 ms frame dBFS energy analysis with adaptive noise floor ($P_{15}$) and speech level ($P_{80}$) thresholding.
- **Unread Omission Detection:** Detects skipped verses ($> 25$ chars/s and acoustic log-prob $< -4.5$) and re-tiles boundaries seamlessly.
- **Quality Signals & Diagnostics:** Generates verse confidence ratings and anomaly flags (`omitted`, `not_at_pause`, `poor_text_match`, `long_verse`, `short_verse`).
- **Constrained Alignment ("Keep My Edits"):** Preserves user-reviewed boundaries as hard constraints, solving the CTC trellis only for intermediate unreviewed verses.
- **Evaluation Suite:** Evaluates alignment accuracy against ground-truth fixtures with metric reporting and CSV export.

---

## Installation

Ensure you have Dart SDK 3.13.5+ installed:

```bash
cd isochron_cli
dart pub get
```

---

## CLI Commands

### 1. Model Management (`model`)

Inspect, download, or delete local ONNX models:

```bash
# Check model download status
dart run bin/isochron_cli.dart model status

# Download and verify the int8 quantized model (~302 MB)
dart run bin/isochron_cli.dart model download

# Delete local model cache
dart run bin/isochron_cli.dart model delete
```

---

### 2. Forced Alignment

Align an audio file against a text file (one verse or sentence per line):

```bash
dart run bin/isochron_cli.dart \
  --text transcript.txt \
  --audio recording.mp3 \
  --lang eng \
  --output alignment.json
```

#### Export Phrase Timing Directly
```bash
dart run bin/isochron_cli.dart \
  --text transcript.txt \
  --audio recording.mp3 \
  --output timings.txt
```

#### CLI Options
| Option | Default | Description |
| :--- | :--- | :--- |
| `--text`, `-t` | *Required* | Path to input text file. |
| `--audio`, `-a` | *Required* | Path to input audio file (`.wav`, `.mp3`, `.m4a`, etc.). |
| `--output`, `-o` | Inferred | Output path (`.json` for JSON, `.txt` for timing text). |
| `--lang` | Auto | ISO 639-3 language code for uroman (e.g. `eng`, `ell`, `heb`, `cmn`). |
| `--lead-in` | `0.19` | Seconds subtracted from speech onset (calibrated optimal: 0.19s). |
| `--star-score` | `-2.0` | Wildcard star token log-probability insertion penalty. |
| `--star-placement` | `segment` | Wildcard placement: `segment` (between verses) or `edges`. |
| `--snap-pauses` | `true` | Snap boundaries to qualifying acoustic silence pauses. |
| `--has-ids` | `false` | Extract leading phrase IDs (auto-detected if text has tabs). |
| `--verbose`, `-v` | `false` | Print detailed progress logs. |

---

### 3. Evaluation Suite (`eval`)

Benchmark aligner performance against ground-truth fixture chapters:

```bash
dart run bin/isochron_cli.dart eval --fixtures ../fixtures --csv results.csv
```

Outputs a full evaluation report including:
- Total and evaluated verses.
- Median, Mean, p90, and p95 absolute error (seconds).
- Percentage of verses within 100 ms, 200 ms, and 500 ms.
- Signed early/late timing bias.
- Total execution time.

---

## Programmatic Dart API Usage

You can embed `isochron_cli` directly in any Dart application:

```dart
import 'dart:io';
import 'package:isochron_cli/isochron_cli.dart';

void main() async {
  final pipeline = MmsPipeline();

  final result = await pipeline.processText(
    rawText: 'In the beginning God created the heaven and the earth.\nAnd the earth was without form, and void.',
    audioPath: 'recording.mp3',
    options: const MmsPipelineOptions(
      languageCode: 'eng',
      leadInSeconds: 0.19,
      snapToPauses: true,
      computeQualityFlags: true,
    ),
    onProgress: (stage, progress) {
      print('[$stage] ${(progress * 100).toStringAsFixed(0)}%');
    },
  );

  for (final fragment in result.fragments) {
    print('${fragment.index}: ${fragment.realStart}s -> ${fragment.realEnd}s '
          '[conf: ${fragment.confidence}, flags: ${fragment.flags}]');
  }
}
```

---

## License

Dedicated to the public domain under the Creative Commons Zero (CC0 1.0 Universal) license.
