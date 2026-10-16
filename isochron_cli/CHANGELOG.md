## 2.0.0 - 2026.10.15

### 🚀 Meta MMS-300M Pure-Dart Engine Rewrite
- **Neural Forced Alignment:** Replaced legacy macOS `say` TTS, MFCC extraction, and DTW with Meta MMS-300M Wav2Vec2 + CTC acoustic model.
- **Pure-Dart ONNX Runtime FFI:** Built direct `dart:ffi` bindings to the native ONNX Runtime C API.
- **Multilingual Tokenizer:** Integrated `uroman: ^1.1.0` supporting 1,130+ languages without per-language dictionaries.
- **Acoustic Energy & Pause Snapping:** 10 ms frame dBFS energy analysis, $P_{15}$/$P_{80}$ adaptive thresholding, and boundary snapping into breath pauses.
- **Unread Omission Detection:** Detects skipped verses ($> 25$ chars/s and log-prob $< -4.5$) and re-tiles boundaries seamlessly.
- **Quality Diagnostics:** Confidence scoring and anomaly flags (`omitted`, `not_at_pause`, `poor_text_match`, `long_verse`, `short_verse`).
- **Constrained Alignment ("Keep My Edits"):** Slices emissions and solves the CTC trellis independently between hard user boundary constraints.
- **CLI Commands:** Added `eval` command for fixture benchmarking and `model` command for model management.

---

## 1.0.0 - 2026.06.17

- Initial version.
