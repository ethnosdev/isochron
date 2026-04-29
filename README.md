# Isochron

**Isochron** is a synthesis-based forced aligner, written in **Dart**. It currently only supports macOS."

It aligns text transcripts to audio recordings by generating a synthetic "anchor" version of the text, analyzing the phonetic structures (MFCCs) of both, and warping time (DTW) to map the known synthetic timestamps onto the real user audio.

Although inspired by Aeneas, this project is not a port of Aeneas to Dart. Rather, the implementation is based on DSP (Digital Signal Processing) theory with the help of Gemini AI and confirmed with human verification. This allows the code to be released to the public domain rather than being limited to Aeneas's more restrictive (though still open-source) license. 

## Features

- **Dart-Based Alignment Engine**: The core algorithm (MFCC extraction, Dynamic Time Warping, Pathfinding) is written entirely in Dart. Uses the Dart `fftea` package for FFT.
- **External Pre-processing**: Uses macOS `afconvert` to normalize user audio to PCM WAV.
- **External Synthesis**: Uses the native macOS `say` command for high-quality synthetic speech generation.
- **Transliteration Support**: Supports custom JSON rules to align non-Latin scripts (e.g., Polytonic Greek, Cyrillic) via `unorm_dart` decomposition and mapping.
-  **Dual Interface:**
    -   **CLI:** For batch processing and automation.
    -   **Flutter Desktop:** A macOS GUI for visual interaction and configuration. (Windows or Linux could easily be added if there is interest.)

## Architecture

1.  **Orchestration:** `IsochronProcessor` manages the pipeline.
2.  **Synthesis:** Text is converted to a "perfect" audio anchor the native macOS `say` utility.
3.  **Signal Processing:**
    *   Audio is normalized to 16kHz Mono 16-bit PCM.
    *   **MFCCs** (Mel-Frequency Cepstral Coefficients) are extracted to represent the "timbre" of the speech.
4.  **Alignment:**
    *   **DTW (Dynamic Time Warping)** finds the optimal path between the User MFCCs and Anchor MFCCs.
    *   Uses a **Sliding Window** approach to reduce memory complexity from $O(N^2)$ to $O(N)$.
5.  **Projection:** The known timestamps from the synthetic audio are projected onto the user audio via the DTW path.

## Project Structure

*   `isochron_cli/`: The core logic engine. Contains all DSP, Math, and Audio processing code.
*   `isochron_flutter/`: A Flutter Desktop application that wraps the CLI logic with a user-friendly UI.

## CLI Usage

Navigate to the `isochron_cli` directory:

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
  --verbose
```

**Options:**
*   `-t, --text`: Path to input text file.
*   `-a, --audio`: Path to input audio file.
*   `-o, --output`: JSON output path (default: `alignment.json`).
*   `--dict`: Path to a JSON file for character transliteration rules.
*   `--pins`: Path to a JSON file containing known-correct timings for specific fragments (see below).
*   `--snap-mode`: Boundary refinement mode. `onset` (default) or `gap-center`.

**Pinned Timings (`--pins`):**

If you have listened to the audio and verified that certain fragments are mis-aligned, you can lock those timestamps in and have the aligner re-compute everything else around them.

Create a JSON file where each key is a **fragment index** (0-based, as a string) and each value is an object with `start` and `end` in seconds:

```json
{
  "0": { "start": 0.0,  "end": 1.4  },
  "7": { "start": 12.3, "end": 15.2 }
}
```

Then pass it with `--pins`:

```bash
dart run bin/isochron_cli.dart \
  --text transcript.txt \
  --audio recording.mp3 \
  --pins pins.json \
  --output result.json
```

Pins do **not** need to be contiguous or in order — you can lock in the first and eighth fragment while leaving everything else to the automatic aligner. The pipeline splits the audio into segments between pins and runs a separate DTW pass in each window, so non-pinned fragments are constrained to exactly the real-audio range their surrounding pins define.

**Snap Mode Example:**
```bash
dart run bin/isochron_cli.dart \
  --text transcript.txt \
  --audio recording.mp3 \
  --snap-mode gap-center \
  --output result.json
```

- `onset`: snaps each fragment toward speech onset (default behaviour).
- `gap-center`: snaps boundaries toward the center of detected silences between neighboring fragments.

## Isochron Studio (Flutter App)

Isochron Studio is a macOS desktop application for batch-aligning audio and text. It uses a **Project-based workflow**, allowing you to manage, align, and edit dozens of files simultaneously without losing your progress.

### 1. Running the App
Navigate to the `isochron_flutter` directory:

```bash
cd isochron_flutter
flutter pub get
flutter run -d macos
```

### 2. Project Workflow

**A. Welcome Screen**
When you launch the app, you can:
*   **Create New Project:** Starts the setup wizard.
*   **Open Project:** Loads an existing `.json` project file. 

**B. Project Creation Wizard**
1.  **Select Files:** Pick your audio files (mp3) and text transcripts (txt).
2.  **Configuration:**
    *   **Verse ID Strategy:** Choose how to generate IDs for your data:
        *   *None:* Do not use IDs.
        *   *IDs are in the text files:* Useful if your transcripts look like `40001001 In the beginning...`. Isochron will strip the ID before alignment and re-attach it to the output data automatically.
        *   *Auto-Generate IDs:* Define a fixed book prefix (e.g., `40`). Isochron will generate sequential IDs automatically based on the file order and line number (e.g., `40001001`).
    *   **Transliteration:** Optionally select a JSON dictionary. The app will analyze all text files and warn you if any characters are missing from your dictionary.
3.  **Pairing:** Drag and drop text files to align them with the correct audio files if the filenames don't match perfectly.

**Example transliteration file (Koine Greek):**
```json
{
  "α": "a",
  "β": "b",
  "γ": "g",
  "θ": "th",
  "φ": "ph"
}
```
*Input:* `ἀρχῇ` -> *Stripped:* `αρχη` -> *Mapped:* `arche` -> *Spoken by Robot:* "arche".

Because the diacritics are stripped by Isochron, there is no need to include diacritics in your JSON map.

**C. The Dashboard**
This is your command center.
*   **Batch Processing:** Click **Run All Pending** to align every file in the queue sequentially.
*   **Status Tracking:** Visual indicators show which files are Pending (Grey), Processing (Spinner), Done (Green), or Error (Red).
*   **Editor Access:** Click the **Edit (Pencil)** icon on any item to open the Waveform Editor.
*   **Project Settings:** Open the top right menu to change your ID strategy or dictionary. You can automatically apply a new ID strategy retroactively to already-aligned files or change the project's snap mode.

**D. The Waveform Editor**
Fine-tune the alignment results visually or manually align difficult files.

*   **Manual Setup & Capture:** If the automatic aligner is failing on a difficult file, you can define timings from scratch.
    1. Click **Manual Setup** to load your text lines as "un-timed" fragments.
    2. Play the audio. 
    3. Every time you hear a new text line begin, press **Enter**. The app will capture that exact moment as the line's start time and automatically extend the previous line to create a gapless boundary.
    4. You can also click the **Capture** button in the list, or **Right-Click** any boundary line on the waveform to delete it.

### 3. Keyboard Shortcuts

| Shortcut        | Action                                                                                                                                                       |
| :-------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Space**       | Play / Pause                                                                                                                                                 |
| **Enter**       | Capture current audio timestamp as the start time for the selected text line.                                                                                |
| **Right Arrow** | Skip to next segment                                                                                                                                         |
| **Left Arrow**  | Skip to previous segment                                                                                                                                     |
| **Cmd + Right** | Nudge segment start **forward** (+0.15s)                                                                                                                     |
| **Cmd + Left**  | Nudge segment start **backward** (-0.15s)                                                                                                                    |
| **L**           | Lock all fragments up to the hovered/focused fragment (bulk pin).                                                                                            |
| **Shift + L**   | Toggle pin on the hovered/focused fragment only.                                                                                                             |

### 4. Export Options

Isochron Studio supports flexible data export from both the Dashboard and the Editor.

*   **JSON:** The standard Isochron format containing IDs, text, start, and end times.
*   **CSV:** Export timing data for databases or spreadsheets.
    *   **Columns:** `id`, `verse_id`, `xxx` (Recording ID), `start`, `end`.
    *   **Batch Export:** From the Dashboard, you can export **all** completed files into a single master CSV.

## License

This project is open-source and dedicated to the public domain (CC0).