# Isochron

**Isochron** is a synthesis-based forced aligner and professional audio/text alignment studio, written in **Dart** and optimized natively for **macOS**. 

It automatically aligns text transcripts to audio recordings. It works by generating a synthetic "anchor" version of your text using macOS's native `say` command, analyzing the phonetic structures (MFCCs) of both the synthetic and real audio, and using Dynamic Time Warping (DTW) to map the exact timestamps onto the real user audio.

The core engine is 100% Dart, based on open-domain DSP theory, and completely free to use.

---

## 🌟 Key Features

* **Pro macOS Interface:** Built with `macos_ui`, featuring a native 3-pane tree sidebar, translucent selection highlights, seamless macOS menu bar integration, and live horizontal progress bars.
* **Smart Auto-Pairing:** Import bulk audio and text files directly into a "Collection". Isochron will naturally sort and link them all automatically into grouped "Tracks".
* **Pro Timeline Navigation:** Navigate the timeline exactly like Logic Pro or Final Cut. Use a two-finger swipe to pan seamlessly, and a two-finger vertical swipe to zoom exponentially. Prefer clicking? Use the new Zoom In/Out buttons right on the toolbar.
* **Dynamic ID Strategies:** Automatically parse verse IDs directly from your text files, or let Isochron auto-generate them sequentially using custom prefixes.
* **Global Transliteration:** Provide a JSON map of non-Latin to Latin characters to instantly apply transliteration rules across your entire project.
* **Headless Batch Processor:** Queue up dozens of alignments in a Collection, hit "Run Alignment on All", and export everything into a unified CSV database when finished.
* **Phrase Timing Export:** Export phrase timing text files per track directly from the editor toolbar when the pair is finalized.

---

## 🚀 Getting Started

Ensure you have Flutter installed, then navigate to the `isochron_flutter` directory:

```bash
cd isochron_flutter
flutter pub get
flutter run -d macos
```

### The Studio Workflow

Isochron uses a streamlined **Project > Collection > Track** hierarchy. You don't have to manually match files before importing them.

1. **Create a Project:** On the welcome screen, click "Create New Project". Pick a location (like your Desktop), and Isochron will instantly build the directory structure (`project.json` and an `alignments/` folder) for you.
2. **Setup Collections:** Create a new Collection (e.g., "Gospel of John") using the folder icon in the sidebar.
3. **Import & Auto-Pair:** Select the Collection and click **Import Files** (or "Select Files..."). Highlight your raw `.mp3`/`.wav` and `.txt`/`.phrase` files. Isochron will naturally sort them and automatically create linked **Tracks**.
4. **Align:** In the Collection batch view, click **Run Alignment on All** to process them automatically while watching the live progress bar, OR double-click a single Track to open the manual **Studio Editor**.

### Export Notes

* **Combined CSV Export:** Available from the File menu or Batch Processor toolbar. It includes only alignments with a status of `done` or `reviewed`.
* **Phrase Timing Export:** Available from the in-editor toolbar for a specific track.
  * Enabled only when status is `done` or `reviewed`.
  * Disabled-state tooltip explains when status is not eligible.
  * Suggested output name is derived from input text filename as:
    `<original-base><separator>timing.txt`.
    * Separator detection supports `-`, `_`, and spaces.
    * If source uses spaces, output suffix separator is normalized to `-`.

---

## 🎛️ Studio Editor Guide

The Studio Editor allows you to manually verify, adjust, or completely dictate timing markers. Isochron safely stores your pinned manual adjustments in a sidecar `-pins.json` file so you never lose your manual work if you re-run the aligner.

### Trackpad & Mouse Controls
Isochron features full native support for Apple Trackpads and standard mice:
* **Two-Finger Swipe Left/Right (or Scroll Wheel):** Smoothly pan the timeline horizontally.
* **Two-Finger Swipe Up/Down (or Ctrl + Scroll):** Smoothly zoom in and out. The zoom is exponentially scaled and anchors perfectly to wherever your mouse cursor is hovering.
* **Pinch-to-Zoom:** Standard trackpad pinching to scale the waveform.
* **Toolbar Buttons:** Dedicated "+" and "-" zoom buttons are available on the top toolbar for accessibility.
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

**Timing Export (same run, same output flag):**
```bash
dart run bin/isochron_cli.dart \
  --text TH-01-GEN-01.txt \
  --audio recording.mp3 \
  --output result.txt
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
* **`--output`:** Single destination path for both JSON and timing exports.
* **`--format` (`json` or `timing`):** Optional explicit output selector. If omitted, format is inferred from `--output` extension (`.json` => JSON, `.txt` => timing), then defaults to JSON.
* **`--snap-mode` (`onset` or `gap`):** Boundary refinement mode. `onset` snaps the fragment toward the speech start. `gap` snaps boundaries toward the center of detected silences.
* **`--snap-offset`:** Milliseconds subtracted from each onset-snapped phrase start (e.g. `250`).
* **`--pins` (Pinned Timings):** Pass a JSON file of known-correct fragment timings (e.g. `{"0": {"start": 0.0, "end": 1.4}}`). The engine will lock these in and only perform DTW in the spaces *between* your pins.

## Architecture

*   `isochron_cli/`: The core logic engine. Contains all DSP, Math, and Audio processing code. Reduces DTW memory complexity from $O(N^2)$ to $O(N)$.
*   `isochron_flutter/`: The native macOS studio application that wraps the CLI logic with a professional workspace GUI.

## License

This project is open-source and dedicated to the public domain (CC0).