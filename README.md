# Isochron

**Isochron** is a high-precision neural forced alignment studio and command-line suite written in Dart, optimized natively for macOS (Apple Silicon).

It aligns spoken audio recordings to written text transcripts across 1,000+ languages, running 100% locally and offline on your Mac.

---

## 🌟 Key Features

- **Meta MMS-300M Neural Engine:** Powered by Meta's Massively Multilingual Speech (Wav2Vec2 + CTC) acoustic model. Supports over 1,130 languages out of the box via universal romanization (`uroman`) without requiring language-specific pronunciation dictionaries.
- **Acoustic Pause Snapping:** Blends 50 Hz CTC Viterbi phonetic alignment with high-resolution 10 ms adaptive energy envelope analysis, snapping verse boundaries directly into natural breath pauses (**45 ms median error, 93.6% within 200 ms**).
- **Listen-and-Nudge Studio:** Review an entire chapter without touching your mouse. Audition individual fragments (`P`), nudge at 50 ms, 150 ms, or 500 ms increments with instant seek-and-play (`Cmd + Arrows`), and mark reviewed (`R`).
- **Quality Signals & Omission Detection:** Automatic confidence scores (0–100%) and color-coded diagnostic flags (`omitted`, `not_at_pause`, `poor_text_match`, `long_verse`, `short_verse`) with quick filter pills (`All`, `Unreviewed`, `Flagged`). Press `F` to jump straight to verses needing review.
- **Headless CLI & Eval Suite:** Run alignments headlessly from terminal scripts, manage ONNX models, and score aligner accuracy against ground-truth fixtures with CSV metric export.

---

## Documentation

- [**Step-by-Step Tutorial**](docs/tutorial.md): A comprehensive walkthrough teaching the complete studio workflow from importing files to reviewing boundaries and exporting timings.
- [**Technical Architecture & Alignment Theory**](docs/technical_details.md): An in-depth engineering deep dive into the MMS-300M model, ONNX Runtime FFI, CTC Viterbi recurrence, adaptive energy modeling, and empirical benchmarks.

---

## Quick Start

### 1. Installing & Running Isochron Studio (macOS)

#### Option A: Download the Installer (Recommended)
1. Download the latest `.dmg` installer from the [**Releases**](../../releases) page.
2. Open the `.dmg` file and drag **Isochron Studio** into your **Applications** folder.
3. Launch **Isochron Studio** from Applications.

#### Option B: Build from Source
If you have Flutter installed on your Mac, you can also run the app directly from source:

```bash
cd isochron_flutter
flutter pub get
flutter run -d macos
```

#### First-Time Model Setup
1. On the **Welcome Screen**, click the **MMS Acoustic Model** card in the bottom-left corner (or click the **Waveform Circle** icon at the bottom of the project sidebar).
2. Click **Download Model** to download the quantized INT8 ONNX model (~302 MB) with automatic SHA-256 verification.
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

Isochron's Studio Editor is designed for hands-on-keyboard productivity (all edits are auto-saved):

| Shortcut                    | Action                    | Description                                                       |
| :-------------------------- | :------------------------ | :---------------------------------------------------------------- |
| **`Space`**                 | **Play / Pause**          | Toggles continuous audio playback.                                |
| **`P`**                     | **Play Fragment**         | Plays only the current fragment and then stops.                   |
| **`←` / `→`**               | **Prev / Next Fragment**  | Skips playback to the previous or next fragment.                  |
| **`Cmd + ←` / `→`**         | **Nudge 150 ms**          | Shifts active boundary by 150 ms and seeks to the new boundary.   |
| **`Cmd + Opt + ←` / `→`**   | **Fine Nudge (50 ms)**    | Micro-adjustment for precise speech onsets.                       |
| **`Cmd + Shift + ←` / `→`** | **Coarse Nudge (500 ms)** | Large adjustment across pauses.                                   |
| **`R`**                     | **Mark Reviewed**         | Marks fragment as reviewed and advances to the next.              |
| **`F`**                     | **Jump to Flag**          | Jumps directly to the next flagged fragment requiring review.     |
| **`Enter`**                 | **Capture Timing**        | Captures current playhead position as boundary start.             |
| **`Cmd + Z` / `⇧⌘Z`**       | **Undo / Redo**           | Undoes or redoes the last boundary or text edit (up to 30 steps). |
| **`Ctrl + ↑` / `↓`**        | **Zoom In / Out**         | Step zooms waveform display.                                      |

---

## 🏗️ Repository Architecture

- [`isochron_cli/`](isochron_cli): The pure-Dart forced aligner engine.
  - `lib/src/ort/`: Direct `dart:ffi` bindings to the native ONNX Runtime C API.
  - `lib/src/mms/`: Tokenizer (`uroman`), sliding-window emissions engine, CTC Viterbi aligner, boundary placer, pause snapper, omission detector, and constrained aligner.
  - `lib/src/audio/`: WAV RIFF chunk parser, dBFS signal energy analyzer, and adaptive silence detector.
  - `lib/src/eval/`: Fixture accuracy scoring suite with CSV export.
- [`isochron_flutter/`](isochron_flutter): The native macOS studio application.
  - `lib/services/`: Long-lived worker isolate managing ONNX model execution, audio playback, user settings, and phrase timing exports.
  - `lib/ui/editor/`: Studio Editor with Transport & Triage control bar, Listen-and-Nudge keyboard shortcuts, inline text editing, and fragment list.
  - `lib/ui/waveform/`: Custom waveform painter with timeline ruler, boundary grab handles, ghost markers, and anchored trackpad pan/zoom.
  - `lib/ui/workspace/`: Project/Collection/Track sidebar tree, batch triage dashboard, group export dialogs, and live file-sync watcher.
  - `lib/ui/settings/`: Acoustic model download panel and project settings.
- [`docs/`](docs): Complete user tutorial and technical architecture documentation.

---

## 📄 License

This project is open-source and dedicated to the public domain under the **Creative Commons Zero (CC0 1.0 Universal)** license.