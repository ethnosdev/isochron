# Isochron CLI

**Isochron** is a synthesis-based forced aligner.

It aligns text to audio by generating a synthetic "anchor" version of the text (using TTS), aligning the synthetic audio to the real user audio using Dynamic Time Warping (DTW), and then projecting the known timestamps from the synthetic version onto the real version.

> **Note:** This project adheres to "Clean Room" design principles. It does not use source code from existing aligners (MFA, Gentle, Aeneas) nor does it use "black box" audio analysis libraries. All DSP (MFCC, FFT, DTW) is implemented in pure Dart.

## Project Status

*   [x] **Phase 1:** Data Structures & Text Parsing
*   [x] **Phase 2:** Anchor Generation (Synthesis & Normalization)
*   [ ] **Phase 3:** Feature Extraction (MFCC / DSP)
*   [ ] **Phase 4:** Alignment (Dynamic Time Warping)
*   [ ] **Phase 5:** Timestamp Projection & JSON Output

## Prerequisites

This tool acts as an orchestrator. To function, it requires the following binaries to be installed and available in your system `PATH`.

### 1. Dart SDK
Requires Dart SDK version `^3.0.0`.

### 2. FFmpeg
Used to normalize user audio and synthetic fragments into a standard format (WAV, 16kHz, Mono, 16-bit).
*   **macOS:** `brew install ffmpeg`
*   **Ubuntu/Debian:** `sudo apt install ffmpeg`
*   **Windows:** [Download builds](https://ffmpeg.org/download.html) and add `bin/` to your Environment Variables.

### 3. eSpeak-ng
Used as the Text-To-Speech (TTS) engine to generate the "Anchor" audio.
*   **macOS:** `brew install espeak-ng`
*   **Ubuntu/Debian:** `sudo apt install espeak-ng`
*   **Windows:** [Download MSI](https://github.com/espeak-ng/espeak-ng/releases) and ensure the executable is in your path.

## Setup

1.  Clone the repository.
2.  Navigate to the CLI folder:
    ```bash
    cd isochron_cli
    ```
3.  Install Dart dependencies:
    ```bash
    dart pub get
    ```

## Usage

Currently, the CLI supports the basic scaffolding.

```bash
dart run bin/isochron_cli.dart --text <path_to_text_file> --audio <path_to_audio_file>
```

Options:

- `-t, --text`: Path to the input transcript (txt).
- `-a, --audio`: Path to the recording (mp3/wav/m4a).
- `-o, --output`: Path to save the output JSON (default: alignment.json).
- `-v, --verbose`: Enable detailed logging.

## Architecture

1. **Parse**: Text is split into fragments.
2. **Synthesize**: We generate anchor.wav using eSpeak. We measure exactly how long each fragment takes to speak.
3. **Process**: We extract Mel-Frequency Cepstral Coefficients (MFCCs) from both anchor.wav and user.wav.
4. **Align**: We use Dynamic Time Warping (DTW) to find the path of least resistance between the two MFCC matrices.
5. **Map**: We translate the known synthetic timestamps into real user timestamps using the DTW path.

## Testing

This project uses a Test-Driven Development (TDD) approach for the DSP logic.

```bash
dart test
```