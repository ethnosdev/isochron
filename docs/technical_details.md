# Isochron Technical Architecture & Alignment Theory

This document provides an engineering deep dive into the algorithms, acoustic models, signal processing pipelines, and dynamic programming formulations implemented in **Isochron**.

---

## 1. High-Level Architecture Overview

Isochron replaces legacy speech synthesis and acoustic MFCC dynamic time warping with a pure-Dart, offline neural forced alignment pipeline powered by Meta's **MMS-300M** (Massively Multilingual Speech) model.

```
+-----------------------------------------------------------------------------+
|                                AUDIO INGESTION                              |
|  Audio File (.wav, .mp3, .m4a) ──► afconvert / WavReader ──► Mono 16 kHz    |
+-----------------------------------------------------------------------------+
                                      │
                                      ▼
+-----------------------------------------------------------------------------+
|                           TEXT TOKENIZATION (uroman)                        |
|  Raw UTF-8 Script ──► uroman ──► Phonetic Normalization ──► Target Tokens   |
+-----------------------------------------------------------------------------+
                                      │
                                      ▼
+-----------------------------------------------------------------------------+
|                      ONNX RUNTIME ACOUSTIC INFERENCE                        |
|  16 kHz Audio ──► 30s Sliding Windows (2s Context) ──► Log-Softmax [T, 32]  |
+-----------------------------------------------------------------------------+
                                      │
                                      ▼
+-----------------------------------------------------------------------------+
|                         CTC VITERBI FORCED ALIGNMENT                        |
|  Log-Prob Matrix + Target Tokens ──► Backpointers ──► Token Time Boundaries |
+-----------------------------------------------------------------------------+
                                      │
                                      ▼
+-----------------------------------------------------------------------------+
|                    ACOUSTIC ENERGY & PAUSE REFINEMENT                       |
|  10ms Energy Frames ──► P15/P80 Adaptive Silence ──► Simple Pause Snapping  |
+-----------------------------------------------------------------------------+
                                      │
                                      ▼
+-----------------------------------------------------------------------------+
|                     QUALITY SIGNALS & CONSTRAINED EDITING                   |
|  find_unread (Omissions) ──► QualityAnalyzer (Flags & Conf) ──► Final JSON  |
+-----------------------------------------------------------------------------+
```

---

## 2. Acoustic Model & ONNX Runtime FFI

### MMS-300M Backbone
The core acoustic model is Meta's `mms-300m` architecture (*Pratap et al., 2023*), consisting of:
- **Feature Encoder:** 7 temporal convolutional layers with kernel sizes `[10, 3, 3, 3, 3, 2, 2]` and strides `[5, 2, 2, 2, 2, 2, 2]`. Total subsampling factor is **320 samples** at 16,000 Hz, producing an output frame rate of **50 Hz** (**20.0 ms per frame**).
- **Transformer Context Network:** 24 Conformer/Transformer layers with 16 attention heads and hidden dimension 1024.
- **CTC Projection Head:** Linear layer projecting to vocabulary classes.

### ONNX Vocabulary & Class Structure
Isochron uses a 32-class projection structure:
- Index `0`: CTC Blank token (`<blank>`).
- Indices `1 .. 30`: Latin characters `a` through `z` and primary phonetic tokens.
- Index `31`: Apostrophe / glottal stop `'`.
- Index `32` (Appended): Wildcard star token ($\langle * \rangle$) with calibrated log-probability insertion penalty $S_* = -2.0$.

### Pure Dart FFI & Native Memory
Instead of relying on third-party Flutter plugin wrappers, `isochron_cli` interfaces directly with `libonnxruntime.dylib` via `dart:ffi`:
- Uses the official C API (`OrtApi`).
- Allocates native tensor buffers with zero-copy views.
- Executes dynamic int8 quantized weights (`model_int8.onnx`, 302.6 MB), optimized for Apple Silicon CPU SIMD execution units.

---

## 3. Sliding Window Inference & Normalization

Continuous recordings (such as 5–15 minute Scripture chapters) exceed typical Wav2Vec2 single-pass context limits. Isochron divides the input audio into overlapping temporal windows:

1. **Window Slicing:** Window length $W = 30.0\text{ s}$ with context padding $C = 2.0\text{ s}$ on either side (total slice duration up to 34.0 s).
2. **Per-Window Normalization:** MMS requires zero-mean and unit-variance audio frames:
   $$\hat{x}_i = \frac{x_i - \mu}{\sqrt{\sigma^2 + \epsilon}}, \quad \text{where } \epsilon = 10^{-7}$$
3. **Context Trimming & Concatenation:** Frames corresponding to context padding are discarded, stitching inner emission frames into a seamless global emission matrix $E \in \mathbb{R}^{T \times 32}$.

---

## 4. Universal Text Tokenization (`uroman`)

Isochron supports over 1,130 languages without requiring language-specific phonetic dictionaries:

1. **Universal Romanizer:** Written scripts (Cyrillic, Greek, Hebrew, Arabic, Devanagari, Hanzi, etc.) are converted to phonetic Latin representations using `uroman` (*Hermjakob et al., 2018*).
2. **Normalization:**
   - Lowercases all characters.
   - Strips diacritics and combining accents.
   - Retains characters `a`–`z` and `'`.
   - Replaces non-alphabetical punctuation and whitespace with blank tokens.
   - Strips isolated numeric digits and reports a warning if unexpanded numbers are detected.
3. **Star Token Placement:** Wildcard star tokens are inserted between segments (`starPlacement = segment`) to absorb unscripted acoustic artifacts, breaths, and inter-verse pauses without degrading speech boundary onsets.

---

## 5. CTC Viterbi Trellis Forced Alignment

For an emission matrix of length $T$ frames and target token sequence of length $N$ tokens:

### State Expansion
Per Graves' CTC formulation (*Graves et al., 2006*), the target sequence is expanded to length $N' = 2N + 1$ by interleaving blank tokens:
$$s = [\text{blank}, c_1, \text{blank}, c_2, \dots, c_N, \text{blank}]$$

### Forward Dynamic Programming
The Viterbi trellis $\alpha(t, j)$ computes the maximum log-probability of aligning prefix $s_{1..j}$ to audio frames $1..t$:

$$\alpha(t, j) = \log P(s_j \mid t) + \max \begin{cases}
\alpha(t-1, j) & \text{(stay)} \\
\alpha(t-1, j-1) & \text{(advance from previous state)} \\
\alpha(t-1, j-2) & \text{(skip blank, if } s_j \ne \text{blank} \text{ and } s_j \ne s_{j-2}\text{)}
\end{cases}$$

### Memory Optimization
- Trellis backpointers are encoded using `Uint8List` flat arrays, reducing heap footprint during backtracking for long chapters.
- Backtracking extracts the optimal frame alignment for each target token $[t_{\text{start}}, t_{\text{end}}]$.

---

## 6. Acoustic Pause Detection & Simple Snap

CTC segmentation reliably finds phonetic transitions, but speech boundaries often fall within acoustic breath silences where CTC emits blank tokens.

### Signal Energy Envelope
- **Frame Size:** 10 ms rectangular windows (160 samples at 16 kHz), offering $2\times$ the temporal resolution of the 20 ms CTC grid.
- **Log Energy (dBFS):**
  $$E_{\text{dBFS}} = 20 \log_{10}\left(\sqrt{\frac{1}{K}\sum_{k=0}^{K-1} x_k^2} + 10^{-12}\right)$$

### Adaptive Noise Modeling
Recordings vary widely in ambient room noise, microphone preamplification, and dynamic range. Rather than hard-coding static decibel thresholds:
- **$P_{15}$ (Noise Floor):** The 15th percentile of frame energy across the entire file provides an empirical estimate of ambient background room tone without influence from active speech.
- **$P_{80}$ (Active Speech Level):** The 80th percentile provides a fast, robust surrogate for ITU-T P.56 active speech level.
- **Adaptive Threshold ($T_{\text{pause}}$):**
  $$T_{\text{pause}} = \text{clamp}(\max(P_{80} - 24\text{ dB}, P_{15} + 8\text{ dB}), -62\text{ dBFS}, -36\text{ dBFS})$$
- **Onset Debounce:** Requires 3 consecutive frames (30 ms) below $T_{\text{pause}}$ to confirm pause onset, preventing unvoiced stop closures (/p, t, k/, typically 20–60 ms) from triggering false pauses.
- **Minimum Duration:** Inter-verse breath pauses must have duration $\ge 100\text{ ms}$.

### Simple Snap Geometry
Given raw CTC boundary $t_{\text{CTC}}$ and qualifying pause $[p_{\text{start}}, p_{\text{end}}]$ within search window $[-1.0\text{ s}, +1.0\text{ s}]$:
$$t_{\text{snap}} = p_{\text{end}} - \text{leadInSeconds}$$
To ensure the boundary never cuts into the trailing speech of the preceding verse:
$$t_{\text{snap}} \ge p_{\text{start}} + 0.35 \times (p_{\text{end}} - p_{\text{start}})$$

### Lead-In Calibration
Empirical testing on multilingual Scripture fixtures demonstrated that calibrating `leadInSeconds` from 0.17s to **0.19s (190 ms)** centered the signed error distribution from $+21\text{ ms}$ bias down to **$+1\text{ ms}$ bias**.

---

## 7. Omission Detection (`find_unread`)

If an audio recording skips or omits a verse present in the text transcript, unconstrained CTC forced alignment will squeeze the omitted verse tokens into a negligible frame slice.

`UnreadDetector` identifies skipped verses using two physically grounded criteria:
1. **Reading Rate Insufficiency:**
   $$\text{ReadingRate} = \frac{\text{length}(\text{text})}{\max(\text{duration}_{\text{speech}}, 0.001)} > 25.0\text{ chars/second}$$
   *(Human speech physically maxes out around 15–20 chars/sec; rates $> 25$ chars/s are physically impossible).*
2. **Acoustic Mismatch:**
   $$\text{meanLogProb} < -4.5$$

When both conditions hold:
- Verse timestamps are set to `-1.0` (`start: -1, end: -1`).
- The `omitted` flag is added.
- Contiguous tiling is stitched directly from the preceding non-omitted verse to the subsequent verse.

---

## 8. Quality Signals & Confidence Scoring

### Confidence Formula
Confidence $C \in [0.0, 1.0]$ blends acoustic log-probability with boundary pause alignment:
$$c_{\text{acoustic}} = \text{clamp}_{0,1}\left(\frac{\text{meanLogProb} + 4.5}{4.0}\right)$$

$$c_{\text{pause}} = \begin{cases}
1.00 & \text{if distance to pause } \le 100\text{ ms (or verse 0)} \\
0.80 & \text{if distance to pause } \le 250\text{ ms} \\
0.50 & \text{otherwise}
\end{cases}$$

$$C = 0.70 \times c_{\text{acoustic}} + 0.30 \times c_{\text{pause}}$$

Penalties are applied for anomalous rate or acoustic match flags, rounded to 2 decimal places.

### Diagnostic Flags
| Flag | Trigger Condition |
| :--- | :--- |
| **`omitted`** | Reading rate $> 25$ chars/s and $\text{meanLogProb} < -4.5$. |
| **`poor_text_match`** | $\text{meanLogProb} < -4.0$ for non-omitted verse. |
| **`not_at_pause`** | Verse boundary falls $> 150\text{ ms}$ from any detected silence gap. |
| **`long_verse`** | Duration $> 10\text{ s}$ and reading rate $< 5.0\text{ chars/s}$. |
| **`short_verse`** | Reading rate $> 22.0\text{ chars/s}$ or duration $< 0.5\text{ s}$. |

---

## 9. "Keep My Edits" Constrained Alignment

When a user manually nudges, drags, or marks a boundary as `reviewed`, that timestamp represents ground truth human judgment.

### Hard Constraint Trellis Slicing
In `ConstrainedAligner`:
1. Fragments with `status == edited` or `status == reviewed` define fixed temporal boundary anchors $T_0, T_1, \dots, T_M$.
2. The global audio emission matrix is sliced between anchors:
   $$\text{startFrame} = \text{round}(T_k / 0.020), \quad \text{endFrame} = \text{round}(T_{k+1} / 0.020)$$
   $$E_{\text{sub}} = E[\text{startFrame} : \text{endFrame}]$$
3. The CTC Viterbi trellis is solved independently for the automatic verses within each slice.
4. Manually reviewed boundaries remain locked to the exact millisecond, preventing alignment errors from propagating across human-verified boundaries.

---

## 10. Empirical Evaluation & Benchmark Metrics

Evaluation was conducted against ground-truth human-verified verse timings across 3 distinct linguistic families and writing systems (78 total verses):

1. **English (Genesis 1):** 31 verses, Latin script, Western Germanic family.
2. **Ancient Greek (Matthew 1):** 25 verses, Greek script, Hellenic family.
3. **Biblical Hebrew (Exodus 1):** 22 verses, Hebrew script (right-to-left), Semitic / Afroasiatic family.

### Comparative Results

| Engine / Stage | Median Error | Mean Error | p95 Error | $\le \mathbf{0.20}$s Accuracy | Early/Late Bias |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Legacy DTW + TTS Engine** | 170 ms | 335 ms | 1,020 ms | 54.8% | -110 ms |
| **Phase 1 MMS Baseline (0.19s leadIn)** | 65 ms | 81 ms | 228 ms | 91.0% | +1 ms |
| **Phase 2 & 3 MMS with Pause Snapping** | **45 ms** | **58 ms** | **214 ms** | **93.6%** | +40 ms |

### Per-Language Accuracy (Phase 2 & 3)
- **Hebrew Exodus 1:** **100.0%** of verses within 0.20s (Mean: 71 ms, p95: 107 ms).
- **Greek Matthew 1:** **96.0%** of verses within 0.20s (Median: 16 ms, Mean: 35 ms, p95: 83 ms).
- **English Genesis 1:** **87.1%** of verses within 0.20s (Median: 50 ms, Mean: 68 ms).

---

## 11. References & Academic Citations

1. **MMS Architecture & Universal Speech Modeling:**  
   Pratap, V., Sriram, A., Tomasello, P., et al. (2023). *Scaling Speech Technology to 1,000+ Languages*. arXiv:2305.13516. Published in *Journal of Machine Learning Research (JMLR)*, 2024.
2. **CTC Segmentation:**  
   Kürzinger, L., Winkelbauer, D., Li, L., et al. (2020). *CTC-Segmentation of Large Corpora for German End-to-End Speech Recognition*. Speech and Computer (SPECOM 2020), Springer, Cham. arXiv:2007.09127.
3. **Universal Romanization:**  
   Hermjakob, U., May, J., & Knight, K. (2018). *Out-of-the-box Universal Romanization Tool (uroman)*. Proceedings of the 56th Annual Meeting of the Association for Computational Linguistics (ACL), Melbourne, Australia.
4. **Active Speech Level & Energy Measurement:**  
   ITU-T Recommendation P.56 (05/93). *Objective measurement of active speech level*. International Telecommunication Union, Geneva.
5. **Voice Activity Detection & Hangover Debounce:**  
   ITU-T Recommendation G.729 Annex B (10/96). *A silence compression scheme for G.729*. International Telecommunication Union, Geneva.
6. **Robust Noise Floor Estimation:**  
   Hirsch, H. G., & Ehrlicher, C. (1995). *Noise estimation techniques for robust speech recognition*. IEEE International Conference on Acoustics, Speech, and Signal Processing (ICASSP 1995), Vol. 1, pp. 153–156.
7. **Wildcard Insertion & Edge Erosion in MMS Trellises:**  
   Ashraf, M. (2023). *ctc-forced-aligner: CTC-based forced alignment tool*. PyTorch / TorchAudio MMS_FA Pipeline documentation.
