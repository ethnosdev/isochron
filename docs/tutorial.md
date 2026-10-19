# Isochron Studio Tutorial

Welcome to **Isochron**! This guide walks you through the complete workflow of using **Isochron Studio** on macOS to align spoken audio with text transcripts, review the results, make quick keyboard adjustments, and export timing files.

---

## Table of Contents
- [Isochron Studio Tutorial](#isochron-studio-tutorial)
  - [Table of Contents](#table-of-contents)
  - [1. Overview \& Prerequisites](#1-overview--prerequisites)
  - [2. Downloading the Neural Model](#2-downloading-the-neural-model)
  - [3. Projects \& Collections](#3-projects--collections)
    - [Creating a New Project](#creating-a-new-project)
  - [4. Importing and Auto-Pairing Audio \& Text](#4-importing-and-auto-pairing-audio--text)
    - [Configuring Project Settings (Optional)](#configuring-project-settings-optional)
  - [5. Running Alignment](#5-running-alignment)
  - [6. The Studio Editor \& Waveform Navigation](#6-the-studio-editor--waveform-navigation)
    - [Waveform \& List Controls](#waveform--list-controls)
  - [7. Listen-and-Nudge Workflow (Keyboard Shortcuts)](#7-listen-and-nudge-workflow-keyboard-shortcuts)
    - [Essential Shortcuts](#essential-shortcuts)
    - [The 5-Second Review Loop](#the-5-second-review-loop)
  - [8. Quality Signals: Confidence Scores \& Flags](#8-quality-signals-confidence-scores--flags)
    - [Confidence Scores](#confidence-scores)
    - [Diagnostic Anomaly Flags](#diagnostic-anomaly-flags)
  - [9. Re-aligning \& "Keep My Edits"](#9-re-aligning--keep-my-edits)
  - [10. Exporting Timings](#10-exporting-timings)
    - [Single Track Timing Export](#single-track-timing-export)
    - [Collection or Project Group Export](#collection-or-project-group-export)

---

## 1. Overview & Prerequisites

Isochron aligns recorded speech to written text using Meta's **MMS-300M** neural forced aligner. It runs **100% offline and locally** on your Mac—no audio or text is ever sent over the internet.

- **System Requirements:** macOS 12+ (Apple Silicon recommended).
- **Audio Formats Supported:** `.mp3`, `.wav`, `.m4a`.
- **Text Formats Supported:** Plain text `.txt` or `.phrases` (one verse, phrase, or sentence per line). Leading tab- or space-delimited phrase IDs (e.g., `40001001\tIn the beginning...` or `1a In the beginning...`) are automatically detected and extracted.
- **Languages Supported:** Over 1,130 languages out of the box via universal romanization (`uroman`).

---

## 2. Downloading the Neural Model

Isochron requires the quantized INT8 MMS-300M ONNX model (~302 MB) to generate acoustic alignments.

1. Launch **Isochron Studio**.
2. On the **Welcome Screen**, click the **MMS Acoustic Model** card at the bottom of the left column (or, if a project is open, click the **Waveform Circle** icon in the bottom-left corner of the sidebar, or click **Manage Acoustic Model...** in Project Settings).
3. The **MMS Acoustic Model** sheet will open. Click **Download Model**.
4. Isochron downloads the quantized model with automatic SHA-256 checksum verification.
5. Once verified, the status indicator turns green and displays **Ready**. You only need to do this once.

---

## 3. Projects & Collections

Isochron organizes work using a clean **Project > Collection > Track** hierarchy:

- **Project:** A folder on your Mac containing your `project.json` configuration and a `collections/` directory.
- **Collection:** A group of related recordings (for example, a book of the Bible, an audiobook chapter series, or a podcast season). Each collection saves its own `collection.json` and `alignments/` subfolder, making projects friendly for shared cloud folders.
- **Track:** A single audio recording paired with its text transcript.

### Creating a New Project
1. Launch Isochron and click **Create New Project...** on the Welcome Screen (or press **`Cmd + N`**).
2. Choose a destination folder and enter a project name, then click **Save**.
3. Isochron creates the project folder and starts you off with a default collection named **First Collection**.

---

## 4. Importing and Auto-Pairing Audio & Text

You don't need to manually match individual audio files to text files one by one. Isochron naturally sorts and pairs them automatically!

1. To create a new collection, click the **New Collection** icon (folder with a `+`) at the top-right of the sidebar. Double-click or right-click the collection and select **Rename** to give it a name (e.g., `Gospel of Mark`).
2. Select the collection in the sidebar, then click **Select Audio & Text Files...** in the main view (or **Import More Files...** if the collection already has tracks).
3. Select **both** your audio files (`.mp3`, `.wav`, `.m4a`) and corresponding text files (`.txt`, `.phrases`) in the file picker.
4. Isochron naturally sorts the filenames (e.g., pairing `MRK_01.mp3` with `MRK_01.txt`, `MRK_02.mp3` with `MRK_02.txt`, ..., `MRK_10.mp3` with `MRK_10.txt`) and creates paired **Tracks** automatically.

> **Healing Moved or Renamed Media:** By default, Isochron links to your original audio and text files on disk. If you ever move or rename your media folder, a warning banner will appear in the Collection view. Click **Locate Missing Media...** and select the new root folder—Isochron will scan it and relink all missing files automatically.

### Configuring Project Settings (Optional)
Click the **Gear icon** (`Project Settings`) at the bottom-left of the sidebar (or press **`Cmd + ,`**):
- **Theme & Collaborator Name:** Switch between System Default, Light Mode, and Dark Mode, and optionally set your collaborator name.
- **Copy imported media into project folder:** Check this box if you want Isochron to copy imported audio and text files directly into the project folder for portable archiving or cloud sharing.
- **Default ID Prefix:** Optional prefix (e.g., `40`, `MRK`, `MAT`) used to auto-generate sequential 9-character IDs (like `MRK001001`) when your transcript files do not contain embedded IDs.
- **Language Code (ISO 639-3):** Specify your 3-letter language code (e.g., `eng` for English, `ell` for Greek, `heb` for Hebrew, `cmn` for Mandarin).
- **Boundary Lead-In (ms):** Sets the breath buffer before speech onsets (default: **190 ms**).

---

## 5. Running Alignment

You can run alignment in two ways:

- **Batch Alignment (Whole Collection):**
  Select a collection in the sidebar to view its **Collection Triage Dashboard**, then click **Run Alignment on All**. Isochron queues all pending/error tracks and processes them sequentially while updating the segmented status bar in real time. Click **Stop Batch** at any time to pause.
- **Single Track Alignment:**
  Click any track in the sidebar or collection list to open the **Studio Editor**, then click **Auto-Align** (the wand icon) in the top toolbar (or right-click the track in the sidebar and choose **Run Auto-Align**).

---

## 6. The Studio Editor & Waveform Navigation

Clicking any track opens the **Studio Editor**, which consists of the **Top Toolbar**, **Waveform View**, **Transport & Triage Control Bar**, and **Fragment List**:

```text
+-----------------------------------------------------------------------------+
| Toolbar: Track Name               | Auto-Align | Export Timing | Zoom -/+   |
+-----------------------------------------------------------------------------+
|  00:00          00:05          00:10          00:15          00:20          |
|  [Waveform View with Playhead, Colored Regions, Handles & Ghost Markers]    |
+-----------------------------------------------------------------------------+
| [Play] [Repeat 1] [Prev] [Next] 00:03.42 / 03:12.00                         |
|   Filter: (All) (Unreviewed) (Flagged) [⚠️ Next Flag (F)]                   |
|                                         [✓ Mark Reviewed (R)] [Undo] [Redo] |
+-----------------------------------------------------------------------------+
| Fragment List:                                                              |
| 1 | [40001001] [Auto] [98%]                                    00:00.00     |
|   | In the beginning God created the heaven and the earth.     [3.4s] ✎ ✓ ⊗ |
|---+-------------------------------------------------------------------------+
| 2 | [40001002] [Edited] [94%]                                  00:03.42     |
|   | And the earth was without form, and void...                [3.8s] ✎ ✓ ⊗ |
+-----------------------------------------------------------------------------+
```

### Waveform & List Controls
- **Pan Timeline:** Two-finger swipe horizontally on your trackpad, scroll horizontally with your mouse, or click-and-drag on an empty area of the waveform.
- **Zoom In / Out:** Two-finger swipe vertically on your trackpad, scroll up/down with your mouse wheel, or hold **`Ctrl` + `↑` / `↓`**. Zooming is smoothly anchored to your mouse cursor. You can also use the **Zoom In / Out** buttons in the toolbar.
- **Scrub & Seek:** Click anywhere on the waveform or click-and-drag along the top timeline ruler to scrub audio.
- **Focus Mode:** **Double-click** any row in the fragment list to automatically zoom and center the waveform on that fragment.
- **Drag Boundary:** Hover over any boundary line on the waveform to reveal its circular midpoint grab handle, then click and drag left or right.
- **Ghost Marker:** If you edit a boundary, a subtle dashed line remains at the original automatic prediction (`autoStart`) so you can compare your adjustment against the AI prediction.
- **Right-Click Context Menu:** Right-click any fragment on the waveform to **Play Fragment (`P`)**, **Mark Reviewed (`R`)**, **Snap Start to Playhead (`Enter`)**, **Reset to Auto Boundary**, or **Clear Timing**.
- **Inline Text Editing:** Click the **Pencil icon** (`Edit Text`) on any fragment row to fix transcript typos inline, then press **`Enter`** to save.

---

## 7. Listen-and-Nudge Workflow (Keyboard Shortcuts)

Isochron is engineered for fast, keyboard-driven verification. You can review an entire chapter without ever reaching for your mouse, and **all edits are auto-saved automatically**.

### Essential Shortcuts

| Key Shortcut                    | Action                       | Description                                                                                                                   |
| :------------------------------ | :--------------------------- | :---------------------------------------------------------------------------------------------------------------------------- |
| **`Space`**                     | **Play / Pause**             | Toggles continuous audio playback.                                                                                            |
| **`P`**                         | **Play Current Fragment**    | Plays only the active fragment from start to end, then stops and resets to the start of the fragment.                         |
| **`←` / `→`**                   | **Previous / Next Fragment** | Skips playback to the previous or next fragment.                                                                              |
| **`Cmd` + `←` / `→`**           | **Standard Nudge (150 ms)**  | Moves active start boundary by 150 ms and **immediately seeks** to the new boundary (continuing playback if already playing). |
| **`Cmd` + `Opt` + `←` / `→`**   | **Fine Nudge (50 ms)**       | Micro-adjustment (50 ms) for exact consonant onsets.                                                                          |
| **`Cmd` + `Shift` + `←` / `→`** | **Coarse Nudge (500 ms)**    | Large adjustment (500 ms) across long pauses or breaths.                                                                      |
| **`R`**                         | **Mark Reviewed & Advance**  | Marks current fragment as **Reviewed** (green badge) and automatically advances to the next fragment.                         |
| **`F`**                         | **Jump to Next Flag**        | Immediately jumps to the next fragment with a diagnostic flag or warning (wraps around the track).                            |
| **`Enter`**                     | **Capture Timing**           | Sets the selected fragment's start boundary to the current playhead position.                                                 |
| **`Cmd` + `Z`**                 | **Undo**                     | Undoes the last boundary or text edit (up to 30 steps).                                                                       |
| **`Cmd` + `Shift` + `Z`**       | **Redo**                     | Redoes the previously undone edit.                                                                                            |
| **`Ctrl` + `↑` / `↓`**          | **Zoom In / Out**            | Zooms the waveform timeline in or out.                                                                                        |

### The 5-Second Review Loop
1. Press **`F`** to jump to the next flagged fragment (or click the **Unreviewed** / **Flagged** filter pills in the control bar).
2. Press **`P`** to audition just that fragment from start to finish.
3. If the start boundary is slightly early or late, press **`Cmd + ←`** or **`Cmd + →`** (or use **`Cmd + Opt + ←/→`** for 50 ms fine-tuning) to nudge it into place.
4. Press **`R`** to mark the fragment as **Reviewed** and automatically advance to the next one!

---

## 8. Quality Signals: Confidence Scores & Flags

Isochron analyzes acoustic emission probabilities and silence gaps to calculate quality metrics for every fragment:

### Confidence Scores
Displayed as a percentage badge on each fragment row:
- **Green (85% – 100%):** High confidence; speech acoustics clearly match the text and the boundary aligns cleanly with a pause.
- **Amber (60% – 84%):** Medium confidence; acceptable match, though worth a quick listen.
- **Red (< 60%):** Low confidence; recommended for manual inspection.

### Diagnostic Anomaly Flags
When Isochron detects a potential issue, it attaches a colored flag badge in the fragment list and highlights the region in **red/terracotta** on the waveform:

- **`Omitted` (Red):** The fragment appears to have been skipped or not read in the recording.
- **`No Pause` (Amber):** The boundary does not fall within a natural acoustic silence gap (speaker spoke continuously without taking a breath).
- **`Poor Match` (Amber):** Low acoustic probability between the spoken audio and the written text (possible pronunciation variation, transcription difference, or background noise).
- **`Long` / `Short` (Teal):** The fragment duration is unusually long or short relative to its character count.

> **Tip:** Press **`F`** (or click **⚠️ Next Flag (F)** in the transport bar) to jump straight from one flagged fragment to the next!

---

## 9. Re-aligning & "Keep My Edits"

If you adjust project settings or re-align a track after making manual edits:

1. Click **Auto-Align** in the Studio Editor toolbar.
2. If the track contains fragments with status **Edited** or **Reviewed**, Isochron presents a confirmation dialog:
   - **"Keep My Edits" (Recommended):** Locks all your edited and reviewed boundaries as permanent anchors, re-aligning only the automatic fragments in between.
   - **"Overwrite All":** Re-aligns the entire track from scratch.
   - **"Cancel":** Leaves the current alignment unchanged.
3. Before overwriting any existing alignment, Isochron automatically saves a **`.bak`** backup file next to your alignment JSON for safety.

---

## 10. Exporting Timings

When your alignments are ready, Isochron gives you flexible export options for single tracks, collections, or entire projects.

### Single Track Timing Export
1. In the Studio Editor toolbar, click **Export Timing** (or right-click the track in the sidebar and choose **Export Timing...**).
2. Choose a destination and click **Save** to export a `.txt` phrase timing file for that track.

### Collection or Project Group Export
1. To export an entire collection, select the collection and click **Export Timings** in the toolbar (or go to **File > Export Collection Timings...**).
2. To export all collections in the project, go to **File > Export Project Timings...** (or press **`Cmd + E`**).
3. In the export dialog, choose your **Export Format**:
   - **Separate files:** Exports each aligned track as its own `.txt` timing file into a destination folder (automatically organized into collection subfolders when exporting a multi-collection project).
   - **Single file:** Combines all aligned tracks into a single `.txt` timing file separated by chapter headers (`\c 1`, `\c 2`, etc.)—ready for direct import into Scripture App Builder and audio-sync publishing tools.

---

🎉 *You're all set! If you're curious about the acoustic math, pause detection algorithms, and ONNX Runtime architecture behind Isochron, check out the [Technical Details](technical_details.md) documentation.*