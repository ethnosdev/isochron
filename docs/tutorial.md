# Isochron Studio Tutorial

Welcome to **Isochron**! This guide walks you through the complete workflow of using the Isochron desktop studio on macOS to align spoken audio with text transcripts, review the results, make quick keyboard adjustments, and export timing files.

---

## Table of Contents
1. [Overview & Prerequisites](#1-overview--prerequisites)
2. [Downloading the Neural Model](#2-downloading-the-neural-model)
3. [Projects & Collections](#3-projects--collections)
4. [Importing and Auto-Pairing Audio & Text](#4-importing-and-auto-pairing-audio--text)
5. [Running Alignment](#5-running-alignment)
6. [The Studio Editor & Waveform Navigation](#6-the-studio-editor--waveform-navigation)
7. [Listen-and-Nudge Workflow (Keyboard Shortcuts)](#7-listen-and-nudge-workflow-keyboard-shortcuts)
8. [Quality Signals: Confidence Scores & Flags](#8-quality-signals-confidence-scores--flags)
9. [Re-aligning & "Keep My Edits"](#9-re-aligning--keep-my-edits)
10. [Exporting Timings](#10-exporting-timings)

---

## 1. Overview & Prerequisites

Isochron aligns recorded speech to written text using Meta's **MMS-300M** neural forced aligner. It runs **100% offline and locally** on your Mac—no audio or text is ever sent over the internet.

- **System Requirements:** macOS 12+ (Apple Silicon recommended).
- **Audio Formats Supported:** `.wav`, `.mp3`, `.m4a`, `.aac`, `.flac`.
- **Text Formats Supported:** Plain text `.txt` (one verse or sentence per line). Tab-delimited phrase IDs (e.g. `40001001\tIn the beginning...`) are automatically detected.
- **Languages Supported:** Over 1,130 languages out of the box via universal romanization.

---

## 2. Downloading the Neural Model

Isochron requires the MMS-300M ONNX model (~302 MB) to generate acoustic alignments.

1. In the app toolbar, click **MMS Model** (or go to **Settings > MMS Model**).
2. The **Model Status Panel** will open. Click **Download Model**.
3. Isochron downloads the quantized model directly from Hugging Face with automatic SHA-256 integrity verification.
4. Once verified, the status displays **Ready**. You only need to do this once.

> **Tip:** If you press **Align** before downloading the model, Isochron will automatically prompt you to open this panel.

---

## 3. Projects & Collections

Isochron organizes work using a clean **Project > Collection > Track** hierarchy:

- **Project:** A folder on your Mac containing your project configuration and collections.
- **Collection:** A group of related recordings (for example, a book of the Bible, an audiobook chapter series, or a podcast season).
- **Track:** A single audio recording paired with its text transcript.

### Creating a New Project
1. Launch Isochron and select **Create New Project** on the welcome screen.
2. Choose a destination folder and enter a project name.
3. Click **Create**.

---

## 4. Importing and Auto-Pairing Audio & Text

You don't need to manually match individual audio files to text files one by one. Isochron automatically sorts and pairs them!

1. In the sidebar, click the **+** button next to **Collections** to create a collection (e.g., `Gospel of Mark`).
2. Select the collection, then click **Import Files** in the main view.
3. Select your audio files (`.mp3`, `.wav`, etc.) and corresponding text files (`.txt`).
4. Isochron matches matching filenames (e.g., `MRK_01.mp3` with `MRK_01.txt`) and creates paired **Tracks** automatically.

### Configuring Project Language & Lead-In (Optional)
Click **Settings** in the sidebar:
- **Language Code (ISO 639-3):** Specify your language code (e.g., `eng` for English, `ell` for Greek, `heb` for Hebrew, `cmn` for Mandarin). Isochron pre-fills this automatically if your filenames use standard Scripture conventions (e.g., `ENG-01-GEN-01.txt`).
- **Boundary Lead-In:** Sets the breath buffer before speech onsets (calibrated default: **190 ms**).

---

## 5. Running Alignment

You can run alignment in two ways:

- **Batch Alignment (Whole Collection):**
  Click **Run Alignment on All** in the collection toolbar. Isochron will queue all tracks, keep the neural model resident in memory, and process each track sequentially while showing real-time progress.
- **Single Track Alignment:**
  Double-click any track in the sidebar or collection list to open the **Studio Editor**, then click **Run Alignment** in the toolbar.

---

## 6. The Studio Editor & Waveform Navigation

Double-clicking any track opens the **Studio Editor**:

```
+-------------------------------------------------------------------------+
| Toolbar: Track Name | Run Alignment | Export Timing | Zoom -/+          |
+-------------------------------------------------------------------------+
|                                                                         |
|  [Waveform View with Playhead, Boundaries, and Ghost Markers]           |
|                                                                         |
+-------------------------------------------------------------------------+
| Verse List:                                                             |
| #1 | [Auto] [98%] In the beginning God created the heaven... | 0.00s->3.42s |
| #2 | [Edited] [94%] And the earth was without form...        | 3.42s->7.18s |
| #3 | [Auto] [91%] And God said, Let there be light...       | 7.18s->9.85s |
+-------------------------------------------------------------------------+
```

### Waveform Controls
- **Pan Timeline:** Two-finger swipe horizontally on your trackpad (or mouse scroll wheel).
- **Zoom In / Out:** Two-finger swipe vertically on your trackpad (or hold `Ctrl` + mouse scroll). The timeline zooms centered on your mouse cursor. You can also use the `+` and `-` zoom toolbar buttons.
- **Active Boundary:** The start line of the currently selected verse is highlighted in **bright gold**.
- **Ghost Marker:** If you adjust a boundary, a subtle dashed line appears at the original automatic prediction (`autoStart`) so you can compare your edit against the AI prediction.
- **Drag Boundary:** Click and drag any boundary line directly on the waveform to reposition it.

---

## 7. Listen-and-Nudge Workflow (Keyboard Shortcuts)

Isochron is engineered for lightning-fast keyboard-driven verification. You can review an entire chapter without ever reaching for your mouse!

### Essential Shortcuts

| Key Shortcut | Action | Description |
| :--- | :--- | :--- |
| **`Space`** | **Play / Pause** | Toggles audio playback. |
| **`←` / `→`** | **Previous / Next Verse** | Changes the active selected verse. |
| **`Cmd` + `←` / `→`** | **Nudge 50 ms** | Moves active boundary back/forward by 50 ms and **auto-replays** from 0.5s before the boundary. |
| **`Cmd` + `Opt` + `←` / `→`** | **Fine Nudge (10 ms)** | Micro-adjustment for exact consonant alignment. |
| **`Cmd` + `Shift` + `←` / `→`** | **Coarse Nudge (250 ms)** | Large jump across long pauses or breaths. |
| **`B`** | **Play Snippet** | Plays 1.5 seconds before and after the active boundary so you can check transition quality. |
| **`R`** | **Mark Reviewed & Advance** | Marks current verse as **Reviewed** (green badge) and automatically selects the next verse. |
| **`F`** | **Jump to Next Flag** | Immediately jumps to the next verse flagged for review (auto-wraps around the track). |
| **`Enter`** | **Capture Timing** | Captures the current playhead position as the boundary start. |
| **`Cmd` + `S`** | **Save** | Saves the alignment to JSON. |

### The 5-Second Review Loop
1. Press **`B`** to audition the boundary transition.
2. If slightly early or late, press **`Cmd + ←`** or **`Cmd + →`** to nudge (the audio instantly auto-replays the change).
3. Press **`R`** to mark reviewed and advance to the next verse.
4. Repeat!

---

## 8. Quality Signals: Confidence Scores & Flags

Isochron analyzes acoustic emission probabilities and background silence gaps to calculate quality metrics for every verse:

### Confidence Scores
Displayed as a percentage pill on each verse:
- **Green (85% - 100%):** High confidence; speech acoustics clearly match text and boundary aligns cleanly with a breath pause.
- **Amber (60% - 84%):** Medium confidence; acceptable match, but may fall in continuous speech.
- **Red (< 60%):** Low confidence; worthy of quick manual inspection.

### Diagnostic Anomaly Flags
When Isochron detects an anomaly, it attaches a colored flag badge and tints the boundary in **amber** on the waveform:

- **`Omitted` (Red):** The verse appears to have been skipped or not read in the recording (unrealistically fast reading rate $> 25$ chars/s and very low acoustic probability).
- **`No Pause` (Orange):** The boundary does not fall within a natural acoustic silence gap (speaker spoke continuously without taking a breath).
- **`Poor Match` (Orange):** Low acoustic probability between the spoken audio and the written text (possible pronunciation variation, transcription typo, or background noise).
- **`Long` / `Short` (Purple):** The verse duration is unusually long or short relative to the character count.

> **Tip:** Press **`F`** to jump straight from one flagged verse to the next!

---

## 9. Re-aligning & "Keep My Edits"

If you adjust project settings or re-align a track after making manual edits:

1. Click **Run Alignment**.
2. If the track contains verses with status **Edited** or **Reviewed**, Isochron presents a safe confirmation dialog:
   - **"Keep My Edits" (Recommended):** Locks all your edited and reviewed boundaries as permanent anchors, re-aligning only the automatic verses in between.
   - **"Overwrite All":** Re-aligns the entire track from scratch.
   - **"Cancel":** Leaves the current alignment unchanged.
3. Before overwriting any existing alignment, Isochron automatically creates a **`.bak`** backup file next to your alignment JSON for safety.

---

## 10. Exporting Timings

When your alignment is verified:

### Single Track Phrase Timing Export
1. In the Studio Editor toolbar, click **Export Timing**.
2. Isochron exports a standardized tab-delimited timing text file (`.txt`) formatted as:
   ```tsv
   index   id       start   end     text
   1       40001001 0.000   3.420   In the beginning...
   2       40001002 3.420   7.180   And the earth was...
   ```
3. The export naming convention automatically defaults to `<audio_base>-timing.txt` or `<text_base>-timing.txt`.

### Batch Collection CSV Export
1. From the macOS menu bar, select **File > Export Combined CSV...** (or click the CSV export icon in the Collection toolbar).
2. Isochron combines all `done` and `reviewed` tracks in the collection into a unified spreadsheet ready for production, translation apps, or video subtitling.

---

🎉 *You're all set! If you're curious about the acoustic math, pause detection algorithms, and ONNX Runtime architecture behind Isochron, check out the [Technical Details](technical_details.md) documentation.*
