# Isochron

**Isochron** is a synthesis-based forced aligner and professional audio/text alignment studio, written in **Dart** and optimized natively for **macOS**. 

It automatically aligns text transcripts to audio recordings. It works by generating a synthetic "anchor" version of your text using macOS's native `say` command, analyzing the phonetic structures (MFCCs) of both the synthetic and real audio, and using Dynamic Time Warping (DTW) to map the exact timestamps onto the real user audio.

The core engine is 100% Dart, based on open-domain DSP theory, and completely free to use.

---

## 🌟 Key Features

* **Pro macOS Interface:** Built with `macos_ui`, featuring sliding sidebars, native translucent selection highlights, and seamless macOS menu bar integration.
* **Smart Auto-Pairing:** Import 50 audio files and 50 text files, click the "Auto-Pair" wand, and Isochron will naturally sort and link them all automatically.
* **Pro Timeline Gestures:** Navigate the timeline exactly like Logic Pro or Final Cut. Two-finger swipe to pan seamlessly, and two-finger vertical swipe (or pinch) for buttery-smooth exponential zooming anchored right to your mouse pointer.
* **Global Transliteration:** Provide a JSON map of non-Latin to Latin characters to instantly apply transliteration rules across your entire project.
* **Headless Batch Processor:** Queue up dozens of alignments, hit "Run All", and export everything into a unified CSV database when finished.
* **Phrase Timing Export:** Export phrase timing text files per alignment from batch tiles or the editor toolbar when the pair is finalized.

---

## 🚀 Getting Started

Ensure you have Flutter installed, then navigate to the `isochron_flutter` directory:

```bash
cd isochron_flutter
flutter pub get
flutter run -d macos
```

### The Studio Workflow

Isochron uses a professional **Asset Pool** architecture. You don't have to manually match files before importing them.

1. **Create a Project:** On the welcome screen, click "Create New Project". Type a name, pick a location (like your Desktop), and Isochron will instantly build the directory structure for you.
2. **Import Assets:** Use the left sidebar to navigate to the **Audio Pool** and **Text Pool**. Click the `+` icon in the top toolbar to import your `.mp3`/`.wav` and `.txt`/`.phrases` files.
3. **Auto-Pair:** Navigate to **Alignments** in the sidebar. Click the **Auto-Pair Unlinked** button (the layered wand icon) to instantly create linked pairs from your imported files.
4. **Align:** Select the **Batch Processor** tab and click "Run All Pending" to process them automatically, OR double-click a single pair to open the manual **Studio Editor**.

### Export Notes

* **Combined CSV Export:** Available from the Batch Processor toolbar. It includes only alignments with status `done` or `reviewed`.
* **Phrase Timing Export:** Available from alignment-list tiles and in-editor toolbar for a specific alignment.
  * Enabled only when status is `done` or `reviewed`.
  * Disabled-state tooltip explains when status is not eligible.
  * Suggested output name is derived from input text filename as:
    `<original-base><separator>timing.txt`.
    * Separator detection supports `-`, `_`, and spaces.
    * If source uses spaces, output suffix separator is normalized to `-`.

---

## 🎛️ Studio Editor Guide

The Studio Editor allows you to manually verify, adjust, or completely dictate timing markers. 

### Trackpad Gestures
Isochron features full native support for Apple Trackpads:
* **Two-Finger Swipe Left/Right:** Smoothly pan the timeline horizontally.
* **Two-Finger Swipe Up/Down:** Smoothly zoom in and out. The zoom is exponentially scaled and anchors perfectly to wherever your mouse cursor is hovering.
* **Pinch-to-Zoom:** Standard trackpad pinching to scale the waveform.
* **Click and Drag:** Grab any boundary line on the waveform to slide it back and forth without moving the playhead.

### Keyboard Shortcuts
Keep your hands on the keyboard to fly through manual adjustments:

| Shortcut           | Action                                                                                                          |
| :----------------- | :-------------------------------------------------------------------------------------------------------------- |
| **Space**          | Play / Pause                                                                                                    |
| **Cmd + S**        | Save Alignment to JSON                                                                                          |
| **Right Arrow**    | Skip to next text segment                                                                                       |
| **Left Arrow**     | Skip to previous text segment                                                                                   |
| **Ctrl + Up/Down** | Step zoom in / out                                                                                              |
| **Cmd + Right**    | Nudge segment boundary **forward** (+0.15s)                                                                     |
| **Cmd + Left**     | Nudge segment boundary **backward** (-0.15s)                                                                    |
| **Enter**          | **Capture Mode:** Instantly capture the current playback time as the start time for the currently selected row. |
| **L**              | Lock (Pin) all fragments up to the selected fragment.                                                           |
| **Shift + L**      | Toggle the Pin lock on just the selected fragment.                                                              |

*(Note: The contextual Nudge feature is smart! If your playhead is hovering close to a boundary, it will automatically grab that boundary. Otherwise, it defaults to nudging the start of the currently playing phrase).*

---

## 💻 Isochron CLI (Command Line Interface)

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
* **`--pins` (Pinned Timings):** Pass a JSON file of known-correct fragment timings (e.g. `{"0": {"start": 0.0, "end": 1.4}}`). The engine will lock these in and only perform DTW in the spaces *between* your pins.

## Architecture

*   `isochron_cli/`: The core logic engine. Contains all DSP, Math, and Audio processing code. Reduces DTW memory complexity from $O(N^2)$ to $O(N)$.
*   `isochron_flutter/`: The native macOS studio application that wraps the CLI logic with a professional workspace GUI.

## License

This project is open-source and dedicated to the public domain (CC0).