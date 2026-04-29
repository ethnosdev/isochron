# Isochron CLI — Technical Overview
### How Text Transcripts Are Aligned with Audio Recordings

---

## Table of Contents
1. [Overview](#overview)
2. [Key Terms & Definitions](#key-terms--definitions)
3. [The Big Picture: A 7-Step Pipeline](#the-big-picture-a-7-step-pipeline)
4. [Step 1 — Parse the Text](#step-1--parse-the-text)
5. [Step 2 — Transliteration (Optional)](#step-2--transliteration-optional)
6. [Step 3 — Generate Anchor Audio (TTS)](#step-3--generate-anchor-audio-tts)
7. [Step 4 — Normalize the User's Audio](#step-4--normalize-the-users-audio)
8. [Step 5 — MFCC Feature Extraction](#step-5--mfcc-feature-extraction)
9. [Step 6 — DTW Alignment](#step-6--dtw-alignment)
10. [Step 7 — Time Projection & Boundary Snapping](#step-7--time-projection--boundary-snapping)
11. [Snap Modes (Onset vs Gap-Center)](#snap-modes-onset-vs-gap-center)
12. [Output Format](#output-format)
13. [File Reference Summary](#file-reference-summary)

---

## Overview

Isochron CLI takes two inputs:

- **A text file** — a transcript, split into lines (one line = one "fragment").
- **An audio file** — a real human reading that same transcript aloud.

It produces a **JSON output** where every line of text is tagged with a precise start and end time in the audio. This is called **forced alignment**.

The core challenge is: the human's recording does not have a built-in clock that says "word X starts at 2.3 seconds." The system must *figure out* those timestamps by comparing the human's voice against a computer-generated reference version of the same text.

---

## Key Terms & Definitions

| Term | Plain-English Definition |
|------|--------------------------|
| **Fragment** | One line of text from the input file. Each fragment will eventually get a start and end time. |
| **Anchor Audio** | A computer-generated (TTS) recording of the text. It acts as a perfect reference with known timings. |
| **Sample Rate (16 kHz)** | Audio is stored as a sequence of numbers (samples). 16,000 samples per second (16 kHz) is CD-quality for speech. |
| **Frame** | A tiny slice of audio — in this code, 20 milliseconds long. Feature extraction happens one frame at a time. |
| **Frame Stride** | How much we slide the frame forward for the next slice — 10 ms here. Frames *overlap*, which gives smoother results. |
| **FFT (Fast Fourier Transform)** | A mathematical trick that converts a time-based audio signal into a list of frequencies and their strengths — like decomposing white light into a rainbow. |
| **Power Spectrum** | The output of an FFT, showing how much energy is present at each frequency. |
| **Mel Scale** | A way of measuring frequency that mirrors how human ears work. High frequencies (e.g. 8000 Hz vs 8100 Hz) are harder for humans to distinguish than low ones (100 Hz vs 200 Hz). The Mel scale "squishes" high frequencies together. |
| **Mel Filterbank** | A set of triangular "buckets" spread across the Mel scale that group nearby frequencies together, producing a more human-like frequency summary. |
| **MFCC** | Mel-Frequency Cepstral Coefficients — a compact 13-number "fingerprint" for each 20ms slice of audio. Used to represent *what a sound sounds like* in a way that's easy to compare. |
| **DCT (Discrete Cosine Transform)** | A compression step that converts 26 filterbank energies into 13 independent coefficients, removing redundant information. |
| **DTW (Dynamic Time Warping)** | An algorithm that compares two sequences of different lengths or speeds by finding the best "elastic" match between them. Like stretching/squishing one sequence until it best fits the other. |
| **Alignment Path** | The output of DTW — a list of pairs `(realFrame, anchorFrame)` that says "frame 42 of the human audio matches frame 38 of the anchor audio." |
| **Boundary Snapping** | A refinement step that micro-adjusts timestamps to align with actual energy onsets in the audio rather than relying purely on DTW math. |
| **Transliteration** | Converting text written in one alphabet into its phonetic equivalent in another. For example, converting Greek "Αθήνα" into the Latin-script pronunciation "Athena" so eSpeak can read it correctly. |
| **TTS (Text-to-Speech)** | Software that converts written text into spoken audio. This code uses **eSpeak-ng**. |
| **FFmpeg** | A widely-used command-line tool for converting and processing audio/video files. Used here to normalize audio to a consistent format. |

---

## The Big Picture: A 7-Step Pipeline

```
[Text File]  ──→  1. Parse Text  ──→  Fragments[]
                                         │
                                    2. Transliterate (optional)
                                         │
                                    3. Generate Anchor Audio (eSpeak TTS)
                                         │                       │
                                    4. Normalize User Audio  anchor timings
                                         │                       │
                                    5. MFCC Extraction ──────────┘
                                      (both audio files)
                                         │
                                    6. DTW Alignment
                                         │
                                    7. Time Projection + Boundary Snapping
                                         │
                                    [alignment.json]
```

The key insight is the **anchor strategy**: instead of trying to directly analyze the human's voice and guess where each word starts, the system creates a perfect synthetic reference. It then uses DTW to find how the human recording "stretches" or "compresses" relative to that perfect reference.

---

## Step 1 — Parse the Text

**File:** `isochron_cli/lib/src/core/text_parser.dart`

The text file is split into lines. Each non-empty line becomes a **Fragment** object.

```dart
// From text_parser.dart
final lines = rawText.split(RegExp(r'\r?\n'));
fragments.add(Fragment(index: counter, text: cleanLine));
```

**Fragment** (`isochron_cli/lib/src/core/fragment.dart`) is the central data structure. It holds:
- `text` — the original line of text
- `spokenText` — a transliterated version (if needed)
- `anchorStart` / `anchorEnd` — timings in the synthetic audio
- `realStart` / `realEnd` — final timings in the human audio (the goal!)

---

## Step 2 — Transliteration (Optional)

**File:** `isochron_cli/lib/src/core/transliterator.dart`

If the text uses a non-Latin alphabet (e.g. Greek, Arabic), eSpeak may struggle to pronounce it correctly. The user can provide a **dictionary file** (a JSON map of character substitutions) via the `--dict` flag.

```json
{ "α": "a", "β": "v", "ñ": "ny" }
```

The `Transliterator` applies these rules character by character, with three priority levels:

1. **Direct match** — exact character found in the dictionary → use the mapped value.
2. **Decompose + strip** — if a character like "ά" isn't in the dictionary, it decomposes it to "α" + a diacritic mark, then strips the mark.
3. **Base mapping** — checks if the stripped base character ("α") is in the dictionary.
4. **Fallback** — if nothing matches, just keep the stripped character as-is.

The result is stored in `frag.spokenText` and used by eSpeak instead of the original text.

---

## Step 3 — Generate Anchor Audio (TTS)

**File:** `isochron_cli/lib/src/synthesis/anchor_generator.dart`

For each fragment, **eSpeak-ng** generates a WAV audio clip of the spoken text. These clips are then normalized by FFmpeg to a consistent format (16 kHz, mono, 16-bit PCM) and concatenated into one long **anchor audio file**.

As the clips are concatenated, the code tracks how many seconds each fragment occupies in the anchor audio:

```dart
// From anchor_generator.dart
frag.setAnchorTiming(start: currentTime, end: currentTime + duration);
currentTime += duration;
```

**Why is this important?** After DTW alignment, these anchor timings become our "rulers." We know that fragment #3 spans seconds 4.2–6.8 in the anchor — and DTW tells us what those anchor frames correspond to in the real audio.

---

## Step 4 — Normalize the User's Audio

**File:** `isochron_cli/lib/src/core/isochron_processor.dart` (lines 50–67)

Before feature extraction, the human's audio is converted to the same format as the anchor — mono, 16 kHz, 16-bit PCM — using FFmpeg:

```
ffmpeg -i user_audio.mp3 -ac 1 -ar 16000 -acodec pcm_s16le user_mono_16k.wav
```

This normalization is critical. If the two audio files had different sample rates or formats, comparing them would be like comparing a photo taken at 72 DPI with one taken at 300 DPI.

---

## Step 5 — MFCC Feature Extraction

**File:** `isochron_cli/lib/src/math/mfcc_extractor.dart`  
**Support file:** `isochron_cli/lib/src/math/dsp_utils.dart`

This is the most technically involved step. It converts each audio file from a raw waveform into a **sequence of 13-number fingerprints** — one fingerprint per 10ms of audio.

### Why MFCC?

You can't directly compare two audio waveforms by subtraction — the same word spoken by two people looks completely different as raw samples. MFCC captures *how the vocal tract is shaped* when making a sound, which is consistent across speakers. Think of it like capturing the "shape" of a sound rather than the exact vibration pattern.

### The Steps (for each 20ms frame):

#### A. Pre-Emphasis
```dart
signal[i] = signal[i] - 0.97 * signal[i - 1];
```
Boosts high frequencies to compensate for the natural tendency of speech to have less energy at high frequencies. Think of it as a treble boost on an equalizer.

#### B. Windowing (Hamming Window)
Each 20ms frame is multiplied by a **Hamming window** — a bell-shaped curve that tapers the edges of the frame to zero. Without this, the hard edges of the frame would introduce artificial high-frequency noise in the FFT.

```
Before:  [0.2, 0.5, 0.8, 0.6, 0.3, 0.1]   ← hard cut at edges
Window:  [0.1, 0.5, 0.9, 0.9, 0.5, 0.1]   ← bell shape
After:   [0.02, 0.25, 0.72, 0.54, 0.15, 0.01]  ← smooth edges
```

#### C. FFT — Convert to Frequencies
The windowed frame is passed through an FFT, which produces a **power spectrum** — essentially: "at 300 Hz, there's this much energy; at 1000 Hz, there's this much energy..."

A 512-sample FFT gives us 256 frequency bins.

#### D. Mel Filterbank
The 256 frequency bins are grouped into **26 Mel-scale buckets** using triangular filters. This mimics how the human ear groups nearby frequencies at high pitches.

**Example (simplified):**
```
Frequency bins:  [100Hz] [200Hz] [300Hz] ... [8000Hz]
                   ↓ triangular filters ↓
Mel buckets:     [bucket1] [bucket2] ... [bucket26]
```

The triangular filters overlap: a frequency of 450 Hz might contribute to both bucket 4 and bucket 5, with different weights (like a crossfade).

#### E. Logarithm
The energy in each of the 26 Mel buckets is passed through `log()`. This mirrors the way human hearing perceives loudness — doubling the sound energy doesn't sound twice as loud to us; it sounds slightly louder. Log scaling captures this perceptual reality.

#### F. DCT — Compress to 13 Numbers
The 26 log-Mel energies are transformed by a **Discrete Cosine Transform (DCT)** into 26 coefficients, and only the first **13** are kept. These 13 numbers are the MFCC vector for this frame.

The DCT decorrelates the energies (removes redundancy between adjacent buckets) and compresses the most important information into the first few coefficients — similar to how JPEG compression works for images.

**Result:** For a 10-second audio clip at 16 kHz, you end up with roughly 1,000 frames × 13 numbers each. This "matrix" is what DTW operates on.

---

## Step 6 — DTW Alignment

**File:** `isochron_cli/lib/src/math/dtw_aligner.dart`  
**Support file:** `isochron_cli/lib/src/math/vector_utils.dart`

### What Is DTW?

Imagine you have two sequences of frames:
- **Anchor MFCC** — the synthetic voice (say, 900 frames)
- **Real MFCC** — the human voice (say, 1100 frames — the human spoke more slowly)

Simple frame-by-frame comparison would fail because the two sequences are different lengths. DTW finds the optimal "elastic" mapping between them.

**Analogy:** Imagine two people clapping to the same song, but one person claps slightly faster in some parts and slower in others. DTW finds which clap from person A corresponds to which clap from person B.

### How DTW Works

DTW builds a matrix where each cell `(i, j)` represents "how well does frame `i` of the real audio match frame `j` of the anchor audio?"

The cost of being at `(i, j)` = distance between the two MFCC vectors + the minimum cost to reach this cell from the three possible predecessors:

```
(i-1, j-1) ← diagonal  = both sequences advance together  (best match)
(i-1, j)   ← up        = real audio has an extra frame (human spoke slowly)
(i, j-1)   ← left      = anchor has an extra frame (human spoke quickly)
```

**Example grid (simplified, 4×4):**

```
         anchor0  anchor1  anchor2  anchor3
real0  [  0.1     inf      inf      inf   ]
real1  [  0.3     0.2      inf      inf   ]
real2  [  0.8     0.3      0.15     inf   ]
real3  [  inf     0.9      0.20     0.18  ]
```

The algorithm fills this grid from top-left to bottom-right, then **backtracks** from bottom-right to top-left to find the lowest-cost path. This path is the alignment.

### Memory Optimization: Sliding Window

A full N×M matrix for long audio would require gigabytes of RAM. The code uses a **band constraint** (radius = 500 frames ≈ 15 seconds): only cells within 500 frames of the diagonal are computed. This cuts memory from O(N×M) to O(N×radius).

```dart
// From dtw_aligner.dart
final int r = max(radius, lengthDiff + 10);   // minimum radius to span length difference
final int jCenter = (i * M / N).round();       // expected diagonal position for row i
final int jStart = max(1, jCenter - r);
final int jEnd   = min(M - 1, jCenter + r);
```

### Output: The Alignment Path

The result is a list of `AlignmentPoint` objects:

```dart
class AlignmentPoint {
  final int realIndex;    // frame index in human audio
  final int anchorIndex;  // frame index in anchor audio
}
```

Example path output (simplified):
```
(realFrame=0,  anchorFrame=0)
(realFrame=1,  anchorFrame=1)
(realFrame=2,  anchorFrame=1)   ← human spoke this sound slightly slower
(realFrame=3,  anchorFrame=2)
(realFrame=4,  anchorFrame=3)
...
```

---

## Step 7 — Time Projection & Boundary Snapping

### Time Projection
**File:** `isochron_cli/lib/src/core/time_projector.dart`

Now the alignment path is used to convert anchor timestamps into real timestamps.

Recall from Step 3: we know fragment #5 spans `anchorStart=4.2s` to `anchorEnd=6.8s` in the synthetic audio. We convert those times to frame numbers, then walk the alignment path to find the corresponding real audio frame numbers.

```dart
// From time_projector.dart
final anchorStartFrame = (frag.anchorStart / frameStride).round();
// Walk path until path[pathIndex].anchorIndex >= anchorStartFrame
final realStart = path[startPoint].realIndex * frameStride;
```

Since each frame is 10ms (`frameStride = 0.010`), multiplying frame number × 0.010 gives time in seconds.

### Boundary Snapping
**File:** `isochron_cli/lib/src/math/boundary_snapper.dart`

DTW gives good approximate timestamps, but they may be off by a few tens of milliseconds. The snapper refines the start time of each fragment by looking at the actual audio energy in a ±250ms window around the projected start time, and finding the exact moment the audio energy jumps above the background noise level.

```dart
// From boundary_snapper.dart
if (localEnergy > noiseFloor) {
  bestIndex = i;
  break; // Found the onset!
}
```

The noise floor is estimated from the first 0.5 seconds of the audio and multiplied by 1.5 to give a comfortable threshold above silence.

---

## Snap Modes (Onset vs Gap-Center)

Isochron now supports two boundary refinement modes:

- `onset` (default): keeps original behaviour by moving each fragment start toward detected speech onset.
- `gap-center`: moves shared boundaries toward the middle of a detected silence gap between neighbouring fragments.

### Where the mode is selected

- **CLI:** `--snap-mode onset|gap-center` (`bin/isochron_cli.dart`)
- **Flutter Studio:** Project Settings -> Snap Mode (`project_settings_dialog.dart`)

### How `gap-center` works

**Files:**  
`isochron_cli/lib/src/core/boundary_strategy.dart`  
`isochron_cli/lib/src/math/boundary_snapping/boundary_snapping_strategy.dart`  
`isochron_cli/lib/src/math/boundary_snapping/normalized_peak_bins.dart`

At a high level:

1. Convert raw audio into small normalized peak bins (10 ms each).
2. Detect runs of low-energy bins (silence regions).
3. For each boundary between fragment `i` and `i+1`, find the most relevant silence run near that seam.
4. Set the shared boundary near the center of that silence run.
5. Respect pinned fragments: pinned sides stay fixed; only unpinned sides move.

This mode is often cleaner when adjacent fragments should meet in the middle of natural pauses rather than at speech onsets.

---

## Output Format

The final JSON output contains one object per fragment:

```json
[
  { "index": 0, "text": "In the beginning", "start": 0.240, "end": 1.850 },
  { "index": 1, "text": "was the word",     "start": 1.860, "end": 3.120 },
  { "index": 2, "text": "and the word",     "start": 3.130, "end": 4.200 }
]
```

- `start` / `end` — timestamps in seconds, rounded to 3 decimal places.
- `id` — included if the input text contained an explicit identifier.

---

## File Reference Summary

| File | Role |
|------|------|
| `bin/isochron_cli.dart` | CLI entry point. Parses command-line flags, loads the dict file, calls `IsochronProcessor.process()`, and writes the JSON output. |
| `lib/src/core/isochron_processor.dart` | **Master pipeline** — orchestrates all 7 steps in order. The best place to understand the full flow. |
| `lib/src/core/fragment.dart` | The `Fragment` data class. Carries text, anchor timings, and real timings through the entire pipeline. |
| `lib/src/core/text_parser.dart` | Splits the raw text file into `Fragment` objects (one per non-empty line). |
| `lib/src/core/transliterator.dart` | Converts non-Latin characters to Latin equivalents using a user-provided dictionary. |
| `lib/src/synthesis/anchor_generator.dart` | Calls eSpeak-ng to synthesize audio for each fragment, normalizes with FFmpeg, concatenates into one anchor WAV, and records anchor timings. |
| `lib/src/math/mfcc_extractor.dart` | Converts raw WAV samples into MFCC feature vectors (13 numbers per 10ms frame). The core audio fingerprinting logic. |
| `lib/src/math/dsp_utils.dart` | Mathematical helpers: `hzToMel`, `melToHz`, `createHammingWindow`, `dct`. |
| `lib/src/math/dtw_aligner.dart` | Runs Dynamic Time Warping between real and anchor MFCC sequences. Returns the alignment path. |
| `lib/src/math/vector_utils.dart` | `euclideanDistance` — measures how "different" two MFCC vectors are. |
| `lib/src/core/time_projector.dart` | Uses the DTW path to convert anchor frame indices → real timestamps for each fragment. |
| `lib/src/math/boundary_snapper.dart` | Refines start timestamps by detecting energy onsets in the real audio around each projected start time. |
| `lib/src/core/boundary_strategy.dart` | Defines snap-mode abstractions (`SnapMode`, `BoundarySnapStrategy`) and the default onset strategy adapter. |
| `lib/src/math/boundary_snapping/boundary_snapping_strategy.dart` | Implements `GapCenterBoundarySnapStrategy` and shared snapping configuration. |
| `lib/src/math/boundary_snapping/normalized_peak_bins.dart` | Builds normalized peak bins and selects silence runs used by gap-centered snapping. |
| `lib/src/audio/wav_utils.dart` | Calculates the duration of a WAV file from its byte size (assumes 16kHz/mono/16-bit format). |
