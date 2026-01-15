This is a technical design document for a **Clean Room Implementation** of a synthesis-based forced aligner.

To maintain "Clean Room" status, you must **not** look at the source code of `aeneas`, `Gentle`, or `MFA`. You must implement the code based solely on the algorithmic descriptions below, which are based on standard Digital Signal Processing (DSP) and Computer Science principles.

### System Architecture
Your Dart application will act as an orchestrator. It requires two external binary dependencies (standard for this type of software):
1.  **FFmpeg:** To convert user audio into a raw, mono, low-sample-rate format (PCM).
2.  **eSpeak-ng (or Festival):** To generate the "Reference" (Synthetic) audio from text.

---

### Phase 1: The Data Structures
You need a structure to hold the text fragments and their calculated times.

**The Fragment Object:**
*   `String text`: The text content.
*   `String id`: Sequential identifier (1, 2, 3...).
*   `double anchorStart`: When this text starts in the *Synthetic* audio (known).
*   `double anchorEnd`: When this text ends in the *Synthetic* audio (known).
*   `double realStart`: The calculated start time in the *User* audio (unknown).
*   `double realEnd`: The calculated end time in the *User* audio (unknown).

---

### Phase 2: Input Processing & Synthesis
The goal here is to create two comparable audio files: the **Real** (User) version and the **Anchor** (Synthetic) version.

#### 1. Text Parsing
Read the input text file. Split the text into fragments based on delimiters (newlines, periods, etc.). Store these in a List of Fragment Objects.

#### 2. The Anchor Generation (The "Synthesis" Step)
You need to generate audio for these fragments using the TTS engine, but you must know exactly how long each fragment is.
*   **Strategy:** Iterate through your list of fragments. For each fragment, call `espeak-ng` via `Process.run` to generate a temporary WAV file.
*   **Calculation:**
    1.  Read the duration of `fragment_1.wav`.
    2.  `Fragment 1 anchorStart` = 0.
    3.  `Fragment 1 anchorEnd` = Duration of `fragment_1.wav`.
    4.  `Fragment 2 anchorStart` = `Fragment 1 anchorEnd`.
    5.  Concatenate the bytes of `fragment_1.wav`, `fragment_2.wav`, etc., into a single file: `anchor_full.wav`.
    *   *Note:* Ensure you strip WAV headers when concatenating PCM data, or use FFmpeg to concat.

#### 3. Audio Normalization
Before mathematical analysis, both `user_audio.mp3` and `anchor_full.wav` must be converted to an identical format.
*   **Target Format:** WAV, Mono, 16-bit PCM, 16000Hz (16kHz).
*   **Why 16kHz?** Human speech intelligibility is mostly below 8kHz. 16kHz captures this (Nyquist theorem) while keeping the array sizes manageable for the math steps.

---

### Phase 3: Feature Extraction (MFCC)
This is the heavy lifting. You cannot compare raw audio waves because the user might speak louder or have background noise. You must compare the "timbre" using **Mel-Frequency Cepstral Coefficients (MFCC)**.

You need to write (or use a library like `scidart`) a processor that takes the raw PCM audio bytes and returns a `List<List<double>>` (The MFCC Matrix).

**The DSP Pipeline:**
1.  **Framing:** Slice the audio into small overlapping windows.
    *   *Standard:* 20ms frame length, 10ms stride (50% overlap).
2.  **Windowing:** Apply a **Hamming Window** function to each frame to reduce spectral leakage at the edges.
3.  **FFT (Fast Fourier Transform):** Convert the time-domain signal (amplitude over time) to frequency-domain (power over frequency).
4.  **Mel Filterbank:** Multiply the FFT power spectrum by a set of triangular filters (usually 26-40 filters) spaced according to the Mel scale (which mimics human hearing sensitivity).
5.  **Logarithm:** Take the log of the filterbank energies (to mimic human loudness perception).
6.  **DCT (Discrete Cosine Transform):** Apply DCT to the log-energies to decorrelate them. Keep the first 12-13 coefficients.

**Result:**
You now have two matrices:
*   `RealMatrix`: Size $[N_{frames} \times 13]$
*   `AnchorMatrix`: Size $[M_{frames} \times 13]$

---

### Phase 4: Alignment (DTW)
You need to align the two matrices. Since the user might speak slower or faster than the robot, the matrices will have different lengths ($N \neq M$). **Dynamic Time Warping (DTW)** solves this.

#### 1. The Cost Matrix
Create a distance function (Euclidean or Cosine distance) to calculate the similarity between any two vectors.
*   Calculate a grid where cell $(i, j)$ represents the distance between `RealFrame[i]` and `AnchorFrame[j]`.

#### 2. The Sakoe-Chiba Band (Optimization)
A full DTW calculation is $O(N \times M)$. For a 1-hour audio file, this will crash your RAM.
*   **Constraint:** You only calculate the cost for cells near the diagonal.
*   **Logic:** It is impossible for the first sentence of the text to align with the last minute of the audio.
*   **Implementation:** Define a "radius" (e.g., 10% of the total length). Only calculate cells where $|i - j| < radius$. Fill other cells with Infinity.

#### 3. Accumulated Cost Calculation
Iterate through the matrix (within the band) to calculate the "Cheapest Path" to get to any cell $(i, j)$.
$$D(i, j) = Cost(i, j) + \min(D(i-1, j), D(i, j-1), D(i-1, j-1))$$

#### 4. Backtracking (The Path)
Start at the bottom-right of the matrix $(N, M)$ and work backwards to $(0, 0)$. At every step, move to the neighbor (Left, Up, or Diagonal) that has the lowest Accumulated Cost.
*   Store this path as a list of coordinate pairs: `[(real_frame_index, anchor_frame_index), ...]`.

---

### Phase 5: Projection (The Output)
Now you map the time.

1.  **The Knowns:** You know `Fragment 1` ends at `AnchorTime = 5.0s`.
2.  **The conversion:** Convert `5.0s` to a frame index.
    *   `AnchorFrameIndex = 5.0s / 0.010s` (assuming 10ms stride).
3.  **The Lookup:** Look at your DTW Path. Find the tuple where the `anchor_frame_index` is closest to the calculated end frame of Fragment 1.
4.  **The Result:** Read the corresponding `real_frame_index` from that tuple.
5.  **Convert back to seconds:**
    *   `RealTime = RealFrameIndex * 0.010s`.

You now have the start and end time of Fragment 1 in the real audio file.

---

### Dart Implementation Notes

#### 1. Use Isolates
The DTW step involves nested loops running millions of times. If you run this on the main Dart thread, your CLI will freeze. Spawn an **Isolate** to handle the MFCC extraction and the DTW calculation.

#### 2. Typed Arrays
Do not use standard Dart `List<double>`. It is too memory inefficient for audio processing.
*   Use `Float64List` or `Float32List` from `dart:typed_data`.

#### 3. Suggested Pub Packages (General Purpose)
To stay "Clean Room," do not use packages specifically designed for "forced alignment." Use general mathematical building blocks:
*   `scidart`: For FFT, Windowing functions, and complex math.
*   `args`: For building the CLI interface.
*   `path`: For file system handling.

### The Algorithm Summary
1.  **Synthesize:** Text $\to$ `Anchor.wav` (Store timestamps).
2.  **Process:** `Anchor.wav` $\to$ `AnchorMFCC`; `Real.wav` $\to$ `RealMFCC`.
3.  **Warp:** DTW(`AnchorMFCC`, `RealMFCC`) $\to$ `Path`.
4.  **Map:** `AnchorTimestamps` + `Path` $\to$ `RealTimestamps`.