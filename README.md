# Isochron

**Isochron** is a synthesis-based forced aligner and professional alignment studio, written in **Dart** and optimized natively for **macOS**. 

It automatically aligns text transcripts to audio recordings. It works by generating a synthetic "anchor" version of your text using macOS's native `say` command, analyzing the phonetic structures (MFCCs) of both the synthetic and real audio, and using Dynamic Time Warping (DTW) to map the exact timestamps onto the real user audio.

The core engine is 100% Dart, based on open-domain DSP theory, and completely free to use.

---

## Getting Started: Isochron Studio (macOS GUI)

Isochron Studio is a native macOS desktop application for batch-aligning and manually editing audio/text pairs. It uses a non-linear, professional studio layout (similar to Xcode or Logic Pro) consisting of **Asset Pools**, a **Main Editor**, and an **Inspector**.

### Running the App
Ensure you have Flutter installed, then navigate to the `isochron_flutter` directory:

```bash
cd isochron_flutter
flutter pub get
flutter run -d macos
```

### The Basic Workflow (5 Steps to Auto-Align)

Isochron uses a flexible **Asset Pool** architecture. You don't have to pair files perfectly before importing them.

1. **Create a Project:** On the welcome screen, click "Create New Project" and select an empty folder on your Mac.
2. **Import Assets:** Use the left sidebar to navigate to the **Audio Pool** and **Text Pool**. Click the `+` icon in the top toolbar to import your `.mp3`/`.wav` and `.txt` files.
3. **Create a Pair:** Navigate to **Alignments** in the sidebar. Click the `+` icon to create a new Alignment Pair.
4. **Link the Files:** Click your new pair. Look at the **Inspector** on the right side of the screen and use the dropdown menus to link your desired Audio and Text files to this pair.
5. **Align:** Double-click the pair to open the **Studio Editor**. Click the **Auto-Align** wand icon in the toolbar. Watch the waveform generate and the text magically snap to the audio!

---

## Studio Interface Guide

### The 3-Pane Layout
* **The Navigator (Left Sidebar):** Manage your workflow. Switch between the Batch Processor, your Alignment queue, and your raw Asset Pools (Audio, Text, Dictionaries).
* **The Inspector (Right Sidebar):** Contextual settings. If you have nothing selected, it shows **Global Project Settings** (Snap Mode, default ID strategies). If you select a pair, it shows linking options for that specific pair.
* **The Main Workspace (Center):** Where the magic happens. Contains data grids for your pools and the Waveform Editor for your pairs.

### Studio Editor Keyboard Shortcuts
When inside the Studio Editor, keep your hands on the keyboard to fly through manual adjustments:

| Shortcut        | Action                                                                                                          |
| :-------------- | :-------------------------------------------------------------------------------------------------------------- |
| **Space**       | Play / Pause                                                                                                    |
| **Right Arrow** | Skip to next text segment                                                                                       |
| **Left Arrow**  | Skip to previous text segment                                                                                   |
| **Cmd + Right** | Nudge segment start **forward** (+0.15s)                                                                        |
| **Cmd + Left**  | Nudge segment start **backward** (-0.15s)                                                                       |
| **Enter**       | **Capture Mode:** Instantly capture the current playback time as the start time for the currently selected row. |
| **L**           | Lock (Pin) all fragments up to the selected fragment.                                                           |
| **Shift + L**   | Toggle the Pin lock on just the selected fragment.                                                              |

### Batch Processing & Exporting
Once you have created multiple Alignment Pairs, click **Batch Processor** in the left sidebar. 
* Click **Run All Pending** to process massive queues sequentially.
* Click **Export CSV** to combine all of your completed `.json` alignments into a single spreadsheet database.

---

## Isochron CLI (Command Line Interface)

If you prefer terminal automation, Isochron can be run head-less. Navigate to the `isochron_cli` directory:

```bash
cd isochron_cli
dart pub get
```

**Basic Alignment:**
```bash
dart run bin/isochron_cli.dart \
  --text transcript.txt \
  --audio recording.mp3 \
  --output result.json
```

**Advanced Usage:**
```bash
dart run bin/isochron_cli.dart \
  --text greek_text.txt \
  --audio greek_audio.mp3 \
  --dict greek_rules.json \
  --snap-mode gap \
  --pins pins.json
```

### CLI Options Explained
* **`--snap-mode` (`onset` or `gap`):** Boundary refinement mode. `onset` snaps the fragment toward the speech start. `gap` snaps boundaries toward the center of detected silences.
* **`--snap-offset`:** Milliseconds subtracted from each onset-snapped phrase start (e.g. `250`).
* **`--dict` (Transliteration):** Provide a JSON map of non-Latin characters to Latin characters. The CLI strips diacritics automatically via `unorm_dart`.
* **`--pins` (Pinned Timings):** Pass a JSON file of known-correct fragment timings (e.g. `{"0": {"start": 0.0, "end": 1.4}}`). The engine will lock these in and only perform DTW in the spaces *between* your pins.

---

## Features & Architecture

* **Dart-Based Alignment Engine:** The core algorithm (MFCC extraction, Dynamic Time Warping, Pathfinding) is written entirely in Dart. Uses the `fftea` package for fast FFT.
* **O(N) DTW Complexity:** Uses a sliding window approach to reduce the memory complexity of Dynamic Time Warping from $O(N^2)$ to $O(N)$, allowing it to process long audio files smoothly.
* **macOS Integration:** 
    * UI built with `macos_ui` for a 100% native desktop feel.
    * Uses `afconvert` natively to normalize user audio to PCM WAV quickly.
    * Uses the native `say` command for high-quality synthetic speech generation.

## Project Structure

*   `isochron_cli/`: The core logic engine. Contains all DSP, Math, and Audio processing code.
*   `isochron_flutter/`: The native macOS studio application that wraps the CLI logic with a professional workspace GUI.

## License

This project is open-source and dedicated to the public domain (CC0).