# Isochron

**Isochron** is a synthesis-based forced aligner, written in **Dart**.

It aligns text transcripts to audio recordings by generating a synthetic "anchor" version of the text, analyzing the phonetic structures (MFCCs) of both, and warping time (DTW) to map the known synthetic timestamps onto the real user audio.

Although inspired by Aeneas, this project is not a port of Aeneas to Dart. Rather, the implementation is based on DSP (Digital Signal Processing) theory with the help of Gemini AI and confirmed with human verification. This allows the code to be released to the public domain rather than being limited to Aeneas's more restrictive (though still open-source) license. 

## Features

- **Dart-Based Alignment Engine**: The core algorithm (MFCC extraction, Dynamic Time Warping, Pathfinding) is written entirely in Dart. Uses the Dart `fftea` package for FFT.
- **External Pre-processing**: Uses FFmpeg to decode user audio (MP3, M4A, etc.) into raw PCM data.
- **External Synthesis**: Uses eSpeak-ng to generate the phonetic reference ("Anchor") audio.
- **Transliteration Support**: Supports custom JSON rules to align non-Latin scripts (e.g., Polytonic Greek, Cyrillic) via `unorm_dart` decomposition and mapping.
-  **Dual Interface:**
    -   **CLI:** For batch processing and automation.
    -   **Flutter Desktop:** A macOS GUI for visual interaction and configuration. (Windows or Linux could easily be added if there is interest.)

## Architecture

1.  **Orchestration:** `IsochronProcessor` manages the pipeline.
2.  **Synthesis:** Text is converted to a "perfect" audio anchor using an external TTS engine.
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

## Prerequisites

Isochron acts as an orchestrator. To respect licensing and keep the core pure, it does **not** bundle external binaries. You must have the following installed:

1.  **FFmpeg:** For audio normalization.
    *   `brew install ffmpeg` (macOS) or `apt install ffmpeg` (Linux).
2.  **eSpeak-ng:** For text-to-speech synthesis.
    *   `brew install espeak-ng` (macOS) or `apt install espeak-ng` (Linux).

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
  --ffmpeg /opt/homebrew/bin/ffmpeg \
  --espeak /opt/homebrew/bin/espeak-ng \
  --verbose
```

**Options:**
*   `-t, --text`: Path to input text file.
*   `-a, --audio`: Path to input audio file.
*   `-o, --output`: JSON output path (default: `alignment.json`).
*   `--dict`: Path to a JSON file for character transliteration rules.
*   `--ffmpeg` / `--espeak`: Custom paths to binaries (useful if they are not in your system PATH).

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
    *   **IDs Checkbox:** Check *"Text files start with ID?"* if your transcripts look like `4001001 In the beginning...`. Isochron will strip the ID before alignment (so the robot doesn't read the numbers) and re-attach it to the output data automatically.
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

**D. The Waveform Editor**
Fine-tune the alignment results visually.

### 3. Keyboard Shortcuts

| Shortcut        | Action                                    |
| :-------------- | :---------------------------------------- |
| **Space**       | Play / Pause                              |
| **Right Arrow** | Skip to next segment                      |
| **Left Arrow**  | Skip to previous segment                  |
| **Cmd + Right** | Nudge segment start **forward** (+0.15s)  |
| **Cmd + Left**  | Nudge segment start **backward** (-0.15s) |

### 4. Export Options

Isochron Studio supports flexible data export from both the Dashboard and the Editor.

*   **JSON:** The standard Isochron format containing IDs, text, start, and end times.
*   **CSV:** Export timing data for databases or spreadsheets.
    *   **Columns:** `id`, `verse_id`, `xxx` (Recording ID), `start`, `end`.
    *   **Batch Export:** From the Dashboard, you can export **all** completed files into a single master CSV.

## License

This project is open-source and dedicated to the public domain (CC0).