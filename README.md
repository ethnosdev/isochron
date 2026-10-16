# Isochron

**Isochron** is a high-precision neural forced alignment studio and command-line suite written in pure **Dart**, optimized natively for **macOS (Apple Silicon)**.

It aligns spoken audio recordings to written text transcripts with 10-millisecond acoustic resolution (**45 ms median error**) across **1,130+ languages**, running **100% locally and offline** on your Mac.

---

## 🌟 Key Features

- 🧠 **Meta MMS-300M Neural Engine:** Powered by Meta's Massively Multilingual Speech (Wav2Vec2 + CTC) acoustic model. Supports over 1,130 languages out of the box via universal romanization (`uroman`) without requiring language-specific pronunciation dictionaries.
- 🎯 **Acoustic Pause Snapping:** Blends 50 Hz CTC Viterbi phonetic alignment with high-resolution 10 ms adaptive energy envelope analysis, snapping verse boundaries directly into natural breath pauses (**45 ms median error, 93.6% within 200 ms**).
- ⌨️ **Listen-and-Nudge Studio:** Review an entire chapter without touching your mouse. Audition boundaries (`B`), nudge at 10 ms, 50 ms, or 250 ms increments with instant auto-replay (`Cmd + Arrows`), and mark reviewed (`R`).
- 🛡️ **"Keep My Edits" Constrained Alignment:** Re-aligning a track never destroys your manual work. Edited and reviewed boundaries are locked as permanent hard constraints, re-aligning only intermediate automatic verses.
- 🔍 **Quality Signals & Omission Detection:** Automatic confidence scores (0–100%) and color-coded diagnostic flags (`omitted`, `not_at_pause`, `poor_text_match`, `long_verse`, `short_verse`). Press `F` to jump straight to verses needing review.
- 🎛️ **Pro macOS Studio GUI:** Built with `macos_ui` featuring smooth Logic Pro-style trackpad panning, exponential pinch-to-zoom, visual ghost markers, and batch collection processing.
- 💻 **Headless CLI & Eval Suite:** Run alignments headlessly from terminal scripts, manage ONNX models, and score aligner accuracy against ground-truth fixtures with CSV metric export.

---

## 📚 Documentation

- [📘 **Step-by-Step Tutorial**](docs/tutorial.md): A comprehensive beginner-friendly walkthrough teaching the complete studio workflow from importing files to exporting timings.
- [🔬 **Technical Architecture & Alignment Theory**](docs/technical_details.md): An in-depth engineering deep dive into the MMS-300M model, ONNX Runtime FFI, CTC Viterbi recurrence, adaptive energy modeling, and empirical benchmarks.

---

## 🚀 Quick Start

### 1. Running the macOS Studio Application

Make sure you have Flutter installed on your Mac:

```bash
cd isochron_flutter
flutter pub get
flutter run -d macos
```

#### First-Time Model Setup
1. In the app toolbar, click **MMS Model**.
2. Click **Download Model** to download the quantized ONNX model (~302 MB) with automatic SHA-256 verification.
3. Once the status shows **Ready**, you are ready to align tracks offline!

---

### 2. Using the Isochron CLI

You can also run forced alignments headlessly from the terminal:

```bash
cd isochron_cli
dart pub get
```

#### Download the Model
```bash
dart run bin/isochron_cli.dart model download
```

#### Align Audio to Text
```bash
dart run bin/isochron_cli.dart \
  --text transcript.txt \
  --audio recording.mp3 \
  --lang eng \
  --output result.json
```

#### Export Phrase Timings Directly
```bash
dart run bin/isochron_cli.dart \
  --text ENG-01-GEN-01.txt \
  --audio recording.mp3 \
  --output timings.txt
```

#### Evaluate Against Ground Truth Fixtures
```bash
dart run bin/isochron_cli.dart eval --fixtures ../fixtures --csv results.csv
```

---

## ⌨️ Studio Keyboard Shortcuts

Isochron's Studio Editor is designed for hands-on-keyboard productivity:

| Shortcut | Action | Description |
| :--- | :--- | :--- |
| **`Space`** | **Play / Pause** | Toggles audio playback. |
| **`←` / `→`** | **Prev / Next Verse** | Selects previous or next verse. |
| **`Cmd + ←` / `→`** | **Nudge 50 ms** | Shifts active boundary by 50 ms with **instant auto-replay**. |
| **`Cmd + Opt + ←` / `→`** | **Fine Nudge (10 ms)** | Micro-adjustment for precise speech onsets. |
| **`Cmd + Shift + ←` / `→`** | **Coarse Nudge (250 ms)** | Large adjustment across pauses. |
| **`B`** | **Play Snippet** | Plays 1.5s before and after the active boundary. |
| **`R`** | **Mark Reviewed** | Marks verse as reviewed and advances to next. |
| **`F`** | **Jump to Flag** | Jumps directly to the next flagged verse requiring review. |
| **`Enter`** | **Capture Timing** | Captures current playhead position as boundary start. |
| **`Cmd + S`** | **Save** | Saves project alignment to JSON. |
| **`Ctrl + ↑` / `↓`** | **Zoom In / Out** | Step zooms waveform display. |

---

## 📊 Benchmark Accuracy Across Languages

Evaluated against ground-truth human-verified verse timings across 3 distinct language families (English, Ancient Greek, Biblical Hebrew — 78 total verses):

```
========================================================================================
                                  EVALUATION REPORT                                     
========================================================================================
Fixture                 Verses   Median(s)   Mean(s)    p95(s)   <=0.2s %   Bias(s)     Time
----------------------------------------------------------------------------------------
english_genesis_1           31       0.050     0.068     0.300      87.1%    +0.060    29.3s
greek_matthew_1             25       0.016     0.035     0.083      96.0%    -0.011    35.1s
hebrew_exodus_1             22       0.075     0.071     0.107     100.0%    +0.071    20.7s
========================================================================================
AGGREGATE (3 fixtures)      78       0.045     0.058     0.214      93.6%    +0.040    85.0s
========================================================================================
```

- **Median Absolute Error:** **45 ms** (down from 170 ms legacy DTW).
- **Mean Absolute Error:** **58 ms** (down from 335 ms legacy DTW).
- **Accuracy Within 200 ms:** **93.6%** (100% in Hebrew, 96% in Greek).

---

## 🏗️ Repository Architecture

- [`isochron_cli/`](file:///Users/suragch/Dev/ethnosdev/isochron/isochron_cli): The pure-Dart forced aligner engine.
  - `lib/src/ort/`: Direct `dart:ffi` bindings to the native ONNX Runtime C API.
  - `lib/src/mms/`: Tokenizer (`uroman`), sliding-window emissions engine, CTC Viterbi aligner, boundary placer, pause snapper, omission detector, and constrained aligner.
  - `lib/src/audio/`: WAV RIFF chunk parser, dBFS signal energy analyzer, and adaptive silence detector.
  - `lib/src/eval/`: Fixture accuracy scoring suite with CSV export.
- [`isochron_flutter/`](file:///Users/suragch/Dev/ethnosdev/isochron/isochron_flutter): The native macOS studio application.
  - `lib/services/`: Long-lived worker isolate managing ONNX model execution without blocking the UI thread.
  - `lib/ui/editor/`: Waveform painter with ghost markers and amber warning tints, Listen-and-Nudge keyboard shortcuts, and verse fragment list.
  - `lib/ui/settings/`: Model download status panel and project language/calibration settings.
- [`docs/`](file:///Users/suragch/Dev/ethnosdev/isochron/docs): Complete user tutorial and technical architecture documentation.

---

## 📄 License

This project is open-source and dedicated to the public domain under the **Creative Commons Zero (CC0 1.0 Universal)** license.