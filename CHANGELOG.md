## 2.0.1 - 2026.10.22

- Fix dialog button text layout issues.
- Fix loading dynamic library errors.

## 2.0.0 - 2026.10.21

### 🚀 Meta MMS-300M Pure-Dart Forced Aligner (Complete Engine Rewrite)
- **Neural Forced Alignment:** Replaced legacy macOS `say` TTS, acoustic MFCC extraction, and Dynamic Time Warping (DTW) with Meta's **MMS-300M** Wav2Vec2 + CTC acoustic model.
- **1,130+ Languages Supported:** Integrated `uroman: ^1.1.0` for universal phonetic romanization and phonetic normalization across scripts (Greek, Hebrew, Cyrillic, Arabic, Devanagari, CJK, etc.) without requiring per-language dictionaries.
- **Sub-10ms Acoustic Precision:** Combines 50 Hz CTC Viterbi decoding with 10 ms adaptive energy envelope pause detection, achieving a **45 ms aggregate median error** and **93.6% accuracy within 200 ms** across multilingual evaluation fixtures (100% in Hebrew, 96% in Greek).
- **Pure-Dart ONNX Runtime FFI:** Built direct `dart:ffi` bindings to the native ONNX Runtime C API with dynamic int8 quantization (`model_int8.onnx`, 302.6 MB), executing offline on Apple Silicon CPU SIMD hardware.
- **Model Status Panel:** In-app management panel to download, inspect, verify SHA-256 integrity, cancel, or delete local ONNX models.

### 🎯 Acoustic Pause Snapping & Omission Detection
- **Adaptive Silence Thresholding:** Analyzes frame RMS energy in dBFS with $P_{15}$ noise floor and $P_{80}$ active speech tracking to adapt to variable recording conditions.
- **Simple Pause Snapping:** Snaps verse boundaries directly into preceding acoustic breath pauses with safety margin clamping and calibrated 190 ms lead-in.
- **Unread Omission Detection (`find_unread`):** Automatically detects skipped verses where reading rate exceeds physical human limits (> 25 chars/s) and acoustic probability drops, marking them with `-1.0` timestamps and `omitted` flags.

### 🔍 Quality Signals & Diagnostic Flags
- **Verse Confidence Scores:** Generates calibrated confidence ratings (0–100%) blending acoustic character probabilities with boundary silence gap placement.
- **Diagnostic Anomaly Flags:** Automatically flags verses with `omitted`, `not_at_pause`, `poor_text_match`, `long_verse`, or `short_verse` to accelerate quality assurance.
- **Keyboard Flag Navigation:** Press `F` to immediately jump to the next verse with diagnostic flags (with auto-wrap).
- **Amber Warning Visuals:** Flagged verse boundaries and waveform regions are highlighted in amber to draw immediate visual attention during review.

### 🛡️ "Keep My Edits" Constrained Alignment
- **Hard Constraint Trellis Solving:** Re-aligning a track preserves user-edited and reviewed boundaries as strict hard constraints, solving the CTC trellis only for intermediate unreviewed verses.
- **Re-alignment Safety:** Safe confirmation dialog offers "Keep My Edits", "Overwrite All", or "Cancel", and automatically saves `.bak` backup files prior to re-alignment.

### ⌨️ Listen-and-Nudge Workflow
- **Keyboard-Driven Review:** Nudge active boundaries forward or backward at 10 ms (`Cmd+Opt+Arrows`), 50 ms (`Cmd+Arrows`), or 250 ms (`Cmd+Shift+Arrows`) with instant auto-replay from 0.5s before the boundary.
- **Boundary Snippet Audition:** Press `B` to play 1.5s before and after the active boundary.
- **Review and Advance:** Press `R` to mark a verse as reviewed and select the next verse.
- **Ghost Markers:** Visual dashed lines display the original AI recommendation when a boundary has been adjusted.

### 💻 CLI & Headless Evaluation Suite
- **CLI Forced Alignment:** Direct headless alignment via `isochron` CLI with `--lang`, `--lead-in`, `--star-score`, and `--snap-pauses` options.
- **Built-in `eval` Command:** Scores alignment accuracy against ground-truth fixtures with full metrics reporting (Median, Mean, p90, p95, % <= 100/200/500ms, bias) and CSV export.
- **Built-in `model` Command:** CLI subcommands `model status`, `model download`, and `model delete`.

### 🧹 Deprecations & Cleanup
- Removed legacy macOS `say` TTS synthesis.
- Removed Pins service, `-pins.json` sidecar files, and manual pin toggling (superseded by "Keep My Edits" constrained alignment).
- Removed Team Collaboration `ClaimService` and claim locks.
- Removed transliteration dictionaries (superseded by uroman).

---

## 1.1.0

- Support for team collaboration.

## 1.0.2 - 2026.09.07

- Improve performance during text alignment.
- Notarize the DMG image.

## 1.0.1 - 2026.09.05

- This patch version fixes a bug with the ID numbering. (#48)
- Download Isochron.dmg to install the new version and replace your old version.

## 1.0.0 - 2026.06.17

- Initial stable release